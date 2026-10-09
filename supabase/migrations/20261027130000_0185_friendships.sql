-- Friendships (Friends, BPP-3).
--
-- One row per pair of players, whichever way the request went:
--   pending  requester_id asked addressee_id
--   accepted mutual friends (requester/addressee keep who asked first)
--   blocked  requester_id (the blocker) blocked addressee_id
-- Decline, cancel, remove and unblock delete the row, so a pair is never in
-- a "declined" limbo and the unique pair index always describes one state.
--
-- The table has RLS on and no grants: everything goes through the SECURITY
-- DEFINER RPCs below so the rules live in SQL and clients stay thin.
--
-- Guests can't send, receive or appear in search. Search is exact-username
-- only (one row at most) and rate limited, so it can't be used to list or
-- enumerate accounts; discovery beyond a known username is the invite code.
-- Requests that can't proceed for reasons the caller shouldn't learn (no such
-- user, blocked) all return 'unavailable', so the result is no oracle either.

create table public.friendships (
  id           uuid primary key default gen_random_uuid(),
  requester_id uuid not null references public.profiles (id) on delete cascade,
  addressee_id uuid not null references public.profiles (id) on delete cascade,
  status       text not null check (status in ('pending', 'accepted', 'blocked')),
  created_at   timestamptz not null default now(),
  responded_at timestamptz,
  check (requester_id <> addressee_id)
);

create unique index friendships_pair_idx
  on public.friendships (least(requester_id, addressee_id), greatest(requester_id, addressee_id));
create index friendships_requester_idx on public.friendships (requester_id, status);
create index friendships_addressee_idx on public.friendships (addressee_id, status);

alter table public.friendships enable row level security;
revoke all on table public.friendships from public, anon, authenticated;

-- The shareable invite code. Rotating it kills old links.
create table private.friend_codes (
  profile_id uuid primary key references public.profiles (id) on delete cascade,
  code       text not null unique,
  created_at timestamptz not null default now()
);
alter table private.friend_codes enable row level security;
revoke all on table private.friend_codes from public, anon, authenticated;

-- ------------------------------------------------------------------ helpers --

-- The signed-in, non-guest, non-deleted caller; raises otherwise.
create function private.friend_caller()
returns uuid
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_me uuid := auth.uid();
  v_profile public.profiles;
begin
  if v_me is null then
    raise exception 'not_authenticated' using errcode = '28000';
  end if;
  select * into v_profile from public.profiles where id = v_me;
  if not found or v_profile.deleted_at is not null then
    raise exception 'not_authenticated' using errcode = '28000';
  end if;
  if v_profile.is_guest then
    raise exception 'guests_cannot_have_friends' using errcode = '42501';
  end if;
  return v_me;
end;
$$;

-- Used by later features (profile reads, feed, leaderboard scope).
create function private.are_friends(p_a uuid, p_b uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1 from public.friendships
     where status = 'accepted'
       and least(requester_id, addressee_id) = least(p_a, p_b)
       and greatest(requester_id, addressee_id) = greatest(p_a, p_b)
  );
$$;

-- The caller's relationship to another player, from the caller's side.
create function private.friend_relationship(p_me uuid, p_other uuid)
returns text
language sql
stable
security definer
set search_path = ''
as $$
  select coalesce(
    (select case
              when f.status = 'accepted' then 'friends'
              when f.status = 'pending' and f.requester_id = p_me then 'outgoing'
              when f.status = 'pending' then 'incoming'
              when f.status = 'blocked' and f.requester_id = p_me then 'blocked'
              else 'none'
            end
       from public.friendships f
      where least(f.requester_id, f.addressee_id) = least(p_me, p_other)
        and greatest(f.requester_id, f.addressee_id) = greatest(p_me, p_other)),
    'none'
  );
$$;

-- Sends (or auto-accepts) a request from p_me to p_target. Targets are
-- already vetted as real, non-guest, non-deleted, non-self by the caller.
create function private.request_friendship(p_me uuid, p_target uuid)
returns text
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row public.friendships;
begin
  select * into v_row from public.friendships f
   where least(f.requester_id, f.addressee_id) = least(p_me, p_target)
     and greatest(f.requester_id, f.addressee_id) = greatest(p_me, p_target);

  if not found then
    begin
      insert into public.friendships (requester_id, addressee_id, status)
      values (p_me, p_target, 'pending');
      return 'requested';
    exception when unique_violation then
      return 'already_requested';
    end;
  end if;

  if v_row.status = 'accepted' then
    return 'already_friends';
  elsif v_row.status = 'blocked' then
    return 'unavailable';
  elsif v_row.requester_id = p_me then
    return 'already_requested';
  end if;

  -- They had already asked us: asking back means yes.
  update public.friendships set status = 'accepted', responded_at = now() where id = v_row.id;
  return 'accepted';
end;
$$;

revoke all on function private.friend_caller() from public, anon, authenticated;
revoke all on function private.are_friends(uuid, uuid) from public, anon, authenticated;
revoke all on function private.friend_relationship(uuid, uuid) from public, anon, authenticated;
revoke all on function private.request_friendship(uuid, uuid) from public, anon, authenticated;

-- ------------------------------------------------------------------ search --

-- Exact username match (ignoring case), at most one row. Hidden from the
-- result: yourself, guests, deleted accounts, and anyone who blocked you.
-- relationship: none | friends | outgoing | incoming | blocked (you blocked them).
create function public.search_users_by_username(p_query text)
returns table (
  profile_id uuid,
  username text,
  display_name text,
  avatar_url text,
  relationship text
)
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  v_me uuid := private.friend_caller();
begin
  perform private.rate_limit_hit('friend_search', 30, interval '1 minute');

  if p_query is null or p_query !~ '^[A-Za-z0-9_]{3,20}$' then
    return;
  end if;

  return query
    select p.id, p.username, p.display_name, p.avatar_url, private.friend_relationship(v_me, p.id)
      from public.profiles p
     where lower(p.username) = lower(p_query)
       and p.id <> v_me
       and not p.is_guest
       and p.deleted_at is null
       and not exists (
         select 1 from public.friendships f
          where f.status = 'blocked' and f.requester_id = p.id and f.addressee_id = v_me
       );
end;
$$;

-- ---------------------------------------------------------------- requests --

-- Returns: requested | accepted (they had already asked you) |
-- already_requested | already_friends | unavailable.
create function public.send_friend_request(p_username text)
returns text
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  v_me uuid := private.friend_caller();
  v_target uuid;
begin
  perform private.rate_limit_hit('friend_request', 30, interval '1 hour');

  if p_username is null or p_username !~ '^[A-Za-z0-9_]{3,20}$' then
    return 'unavailable';
  end if;

  select p.id into v_target
    from public.profiles p
   where lower(p.username) = lower(p_username)
     and p.id <> v_me and not p.is_guest and p.deleted_at is null;
  if not found then
    return 'unavailable';
  end if;

  return private.request_friendship(v_me, v_target);
end;
$$;

-- The next four return true when something changed, false when there was
-- nothing to act on, so clients can be idempotent.
create function public.accept_friend_request(p_user_id uuid)
returns boolean
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  v_me uuid := private.friend_caller();
begin
  update public.friendships
     set status = 'accepted', responded_at = now()
   where status = 'pending' and requester_id = p_user_id and addressee_id = v_me;
  return found;
end;
$$;

create function public.decline_friend_request(p_user_id uuid)
returns boolean
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  v_me uuid := private.friend_caller();
begin
  delete from public.friendships
   where status = 'pending' and requester_id = p_user_id and addressee_id = v_me;
  return found;
end;
$$;

create function public.cancel_friend_request(p_user_id uuid)
returns boolean
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  v_me uuid := private.friend_caller();
begin
  delete from public.friendships
   where status = 'pending' and requester_id = v_me and addressee_id = p_user_id;
  return found;
end;
$$;

create function public.remove_friend(p_user_id uuid)
returns boolean
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  v_me uuid := private.friend_caller();
begin
  delete from public.friendships
   where status = 'accepted'
     and least(requester_id, addressee_id) = least(v_me, p_user_id)
     and greatest(requester_id, addressee_id) = greatest(v_me, p_user_id);
  return found;
end;
$$;

-- Blocking replaces any existing friendship or request between the two. If
-- they already blocked you it changes nothing (their block stays theirs).
create function public.block_user(p_user_id uuid)
returns boolean
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  v_me uuid := private.friend_caller();
  v_row public.friendships;
begin
  if p_user_id is null or p_user_id = v_me
     or not exists (select 1 from public.profiles where id = p_user_id and not is_guest and deleted_at is null) then
    return false;
  end if;

  select * into v_row from public.friendships f
   where least(f.requester_id, f.addressee_id) = least(v_me, p_user_id)
     and greatest(f.requester_id, f.addressee_id) = greatest(v_me, p_user_id);

  if found and v_row.status = 'blocked' then
    return v_row.requester_id = v_me;
  end if;

  delete from public.friendships where id = v_row.id;
  insert into public.friendships (requester_id, addressee_id, status, responded_at)
  values (v_me, p_user_id, 'blocked', now());
  return true;
end;
$$;

create function public.unblock_user(p_user_id uuid)
returns boolean
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  v_me uuid := private.friend_caller();
begin
  delete from public.friendships
   where status = 'blocked' and requester_id = v_me and addressee_id = p_user_id;
  return found;
end;
$$;

-- ------------------------------------------------------------------- lists --

create function public.list_friends()
returns table (
  profile_id uuid,
  username text,
  display_name text,
  avatar_url text,
  since timestamptz
)
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_me uuid := private.friend_caller();
begin
  return query
    select p.id, p.username, p.display_name, p.avatar_url, coalesce(f.responded_at, f.created_at)
      from public.friendships f
      join public.profiles p
        on p.id = case when f.requester_id = v_me then f.addressee_id else f.requester_id end
     where f.status = 'accepted'
       and v_me in (f.requester_id, f.addressee_id)
       and p.deleted_at is null
     order by lower(p.username), p.id;
end;
$$;

-- direction: incoming (they asked you) | outgoing (you asked them).
create function public.list_friend_requests()
returns table (
  direction text,
  profile_id uuid,
  username text,
  display_name text,
  avatar_url text,
  created_at timestamptz
)
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_me uuid := private.friend_caller();
begin
  return query
    select case when f.addressee_id = v_me then 'incoming' else 'outgoing' end,
           p.id, p.username, p.display_name, p.avatar_url, f.created_at
      from public.friendships f
      join public.profiles p
        on p.id = case when f.requester_id = v_me then f.addressee_id else f.requester_id end
     where f.status = 'pending'
       and v_me in (f.requester_id, f.addressee_id)
       and p.deleted_at is null
     order by f.created_at desc, p.id;
end;
$$;

create function public.list_blocked_users()
returns table (
  profile_id uuid,
  username text,
  display_name text,
  avatar_url text,
  blocked_at timestamptz
)
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_me uuid := private.friend_caller();
begin
  return query
    select p.id, p.username, p.display_name, p.avatar_url, f.created_at
      from public.friendships f
      join public.profiles p on p.id = f.addressee_id
     where f.status = 'blocked' and f.requester_id = v_me and p.deleted_at is null
     order by f.created_at desc, p.id;
end;
$$;

-- ------------------------------------------------------------- invite code --

create function private.new_friend_code()
returns text
language sql
volatile
set search_path = ''
as $$ select upper(substr(replace(gen_random_uuid()::text, '-', ''), 1, 12)) $$;
revoke all on function private.new_friend_code() from public, anon, authenticated;

-- The caller's invite code, created on first use. The invite link is
-- <site>/friends/invite/<code>; the clients build it, SQL only owns the code.
create function public.get_my_friend_code()
returns text
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  v_me uuid := private.friend_caller();
  v_code text;
begin
  select code into v_code from private.friend_codes where profile_id = v_me;
  if found then
    return v_code;
  end if;

  loop
    begin
      insert into private.friend_codes (profile_id, code)
      values (v_me, private.new_friend_code())
      on conflict (profile_id) do nothing;
      select code into v_code from private.friend_codes where profile_id = v_me;
      return v_code;
    exception when unique_violation then
      null; -- astronomically unlikely code collision; draw again
    end;
  end loop;
end;
$$;

-- Replaces the code so previously shared links stop working.
create function public.reset_friend_code()
returns text
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  v_me uuid := private.friend_caller();
  v_code text;
begin
  perform private.rate_limit_hit('friend_code_reset', 10, interval '1 hour');
  loop
    begin
      insert into private.friend_codes (profile_id, code)
      values (v_me, private.new_friend_code())
      on conflict (profile_id) do update set code = excluded.code, created_at = now()
      returning code into v_code;
      return v_code;
    exception when unique_violation then
      null;
    end;
  end loop;
end;
$$;

-- Who an invite code belongs to, so the invite page can say "X invited you".
-- Zero rows for an unknown code, your own code, a guest/deleted owner, or an
-- owner who blocked you.
create function public.lookup_friend_code(p_code text)
returns table (
  profile_id uuid,
  username text,
  display_name text,
  avatar_url text,
  relationship text
)
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  v_me uuid := private.friend_caller();
begin
  perform private.rate_limit_hit('friend_code', 60, interval '1 hour');

  return query
    select p.id, p.username, p.display_name, p.avatar_url, private.friend_relationship(v_me, p.id)
      from private.friend_codes c
      join public.profiles p on p.id = c.profile_id
     where c.code = upper(trim(coalesce(p_code, '')))
       and p.id <> v_me and not p.is_guest and p.deleted_at is null
       and not exists (
         select 1 from public.friendships f
          where f.status = 'blocked' and f.requester_id = p.id and f.addressee_id = v_me
       );
end;
$$;

-- Using someone's code asks to be their friend (they still accept); it does
-- not add you silently, so a leaked link can't attach strangers to an
-- account's activity. Same results as send_friend_request.
create function public.redeem_friend_code(p_code text)
returns text
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  v_me uuid := private.friend_caller();
  v_target uuid;
begin
  perform private.rate_limit_hit('friend_code', 60, interval '1 hour');

  select p.id into v_target
    from private.friend_codes c
    join public.profiles p on p.id = c.profile_id
   where c.code = upper(trim(coalesce(p_code, '')))
     and p.id <> v_me and not p.is_guest and p.deleted_at is null;
  if not found then
    return 'unavailable';
  end if;

  return private.request_friendship(v_me, v_target);
end;
$$;

-- ------------------------------------------------------------------- grants --

do $$
declare
  r record;
begin
  for r in
    select p.oid::regprocedure as sig
      from pg_proc p
     where p.pronamespace = 'public'::regnamespace
       and p.proname in (
         'search_users_by_username', 'send_friend_request', 'accept_friend_request',
         'decline_friend_request', 'cancel_friend_request', 'remove_friend', 'block_user',
         'unblock_user', 'list_friends', 'list_friend_requests', 'list_blocked_users',
         'get_my_friend_code', 'reset_friend_code', 'lookup_friend_code', 'redeem_friend_code'
       )
  loop
    execute format('revoke all on function %s from public, anon', r.sig);
    execute format('grant execute on function %s to authenticated', r.sig);
  end loop;
end $$;

-- A deleted account leaves no friendships, blocks or invite code behind.
create or replace function public.delete_own_account()
returns void
language plpgsql security definer set search_path = ''
as $$
declare
  v_user uuid := auth.uid();
begin
  if v_user is null then
    raise exception 'not_authenticated' using errcode = '42501';
  end if;

  update public.profiles
     set display_name = 'Deleted player',
         avatar_url = null,
         username = null,
         deleted_at = coalesce(deleted_at, now())
   where id = v_user;

  delete from public.friendships where v_user in (requester_id, addressee_id);
  delete from private.friend_codes where profile_id = v_user;

  update auth.users
     set banned_until = now() + interval '100 years'
   where id = v_user;
end;
$$;
