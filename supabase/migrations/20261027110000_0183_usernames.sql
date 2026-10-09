-- Unique usernames (Friends, BPP-3).
--
-- display_name stays the non-unique friendly name. username is the handle
-- people search for and share: 3-20 letters, digits or underscore, unique
-- ignoring case, and kept as typed. The unique index is the source of truth;
-- claim_username and username_available are the only paths clients use, so
-- the rules are never reimplemented outside SQL.
--
-- Every real account always has a username: the new-user trigger and the
-- guest-upgrade trigger derive one from the display name (numeric suffix on
-- collision), and signup/edit-profile lets the player change it. Guests get
-- none, and a deleted account releases its name.

-- ------------------------------------------------------- rate limit helper --
-- A tiny fixed-window counter keyed by caller and bucket. Used by the
-- username and friend-search RPCs so they can't be hammered to enumerate
-- accounts. Failures that RAISE roll their own increment back, so RPCs that
-- must count every attempt return a result instead of raising.

create table private.rate_limits (
  user_id      uuid not null references auth.users (id) on delete cascade,
  bucket       text not null,
  window_start timestamptz not null,
  hits         integer not null,
  primary key (user_id, bucket)
);
alter table private.rate_limits enable row level security;
revoke all on table private.rate_limits from public, anon, authenticated;

create function private.rate_limit_hit(p_bucket text, p_max integer, p_window interval)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_hits integer;
begin
  insert into private.rate_limits as r (user_id, bucket, window_start, hits)
  values (auth.uid(), p_bucket, now(), 1)
  on conflict (user_id, bucket) do update
    set hits = case when r.window_start <= now() - p_window then 1 else r.hits + 1 end,
        window_start = case when r.window_start <= now() - p_window then now() else r.window_start end
  returning r.hits into v_hits;

  if v_hits > p_max then
    raise exception 'rate_limited' using errcode = '54000';
  end if;
end;
$$;
revoke all on function private.rate_limit_hit(text, integer, interval) from public, anon, authenticated;

-- ---------------------------------------------------------------- username --

alter table public.profiles add column username text;

alter table public.profiles
  add constraint profiles_username_format check (username is null or username ~ '^[A-Za-z0-9_]{3,20}$'),
  add constraint profiles_username_not_guest check (username is null or not is_guest);

create unique index profiles_username_lower_idx on public.profiles (lower(username));

create function private.username_reserved(p_username text)
returns boolean
language sql
immutable
set search_path = ''
as $$
  select lower(p_username) = any (array[
    'admin', 'administrator', 'support', 'help', 'staff', 'moderator', 'mod', 'system',
    'ballparty', 'ball_party', 'official', 'root', 'null', 'undefined', 'anonymous', 'deleted',
    'guest', 'you', 'me', 'friends', 'api', 'www'
  ]);
$$;

create function private.derive_username_base(p_name text)
returns text
language sql
immutable
set search_path = ''
as $$
  select case
    when length(b) = 0 then 'player'
    when length(b) < 3 then rpad(b, 3, '_')
    else left(b, 20)
  end
  from (
    select regexp_replace(
             regexp_replace(trim(coalesce(p_name, '')), '\s+', '_', 'g'),
             '[^A-Za-z0-9_]', '', 'g'
           ) as b
  ) s;
$$;

-- Gives a username-less real account one derived from its display name. The
-- unique index decides collisions: try the base, then base2, base3, ... and
-- fall back to a random suffix if a name is very crowded. Never raises for a
-- collision, so it cannot fail a signup.
create function private.assign_username(p_id uuid)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_name text;
  v_base text;
  v_try integer := 0;
  v_candidate text;
begin
  select display_name into v_name
    from public.profiles
   where id = p_id and username is null and not is_guest and deleted_at is null;
  if not found then
    return;
  end if;

  v_base := private.derive_username_base(v_name);
  loop
    v_try := v_try + 1;
    v_candidate := case
      when v_try = 1 then v_base
      when v_try <= 50 then left(v_base, 20 - length(v_try::text)) || v_try::text
      else left(v_base, 15) || '_' || lpad(floor(random() * 10000)::text, 4, '0')
    end;

    if not private.username_reserved(v_candidate) then
      begin
        update public.profiles set username = v_candidate where id = p_id and username is null;
        return;
      exception when unique_violation then
        null;
      end;
    end if;

    if v_try > 200 then
      raise exception 'username_exhausted';
    end if;
  end loop;
end;
$$;
revoke all on function private.username_reserved(text) from public, anon, authenticated;
revoke all on function private.derive_username_base(text) from public, anon, authenticated;
revoke all on function private.assign_username(uuid) from public, anon, authenticated;

-- New accounts and upgraded guests get a username as soon as they are real.
create or replace function private.handle_new_user()
returns trigger
language plpgsql security definer set search_path = ''
as $$
begin
  insert into public.profiles (id, display_name, avatar_url, is_guest)
  values (
    new.id,
    left(
      coalesce(
        nullif(trim(new.raw_user_meta_data ->> 'display_name'), ''),
        nullif(trim(new.raw_user_meta_data ->> 'full_name'), ''),
        nullif(trim(new.raw_user_meta_data ->> 'name'), ''),
        nullif(split_part(coalesce(new.email, ''), '@', 1), ''),
        'Player'
      ),
      16
    ),
    coalesce(
      nullif(trim(new.raw_user_meta_data ->> 'avatar_url'), ''),
      nullif(trim(new.raw_user_meta_data ->> 'picture'), '')
    ),
    coalesce(new.is_anonymous, false)
  )
  on conflict (id) do nothing;

  perform private.assign_username(new.id);
  return new;
end;
$$;

create or replace function private.sync_guest_profile()
returns trigger
language plpgsql security definer set search_path = ''
as $$
begin
  if new.is_anonymous is distinct from old.is_anonymous then
    update public.profiles set is_guest = coalesce(new.is_anonymous, false) where id = new.id;
    if not coalesce(new.is_anonymous, false) then
      perform private.assign_username(new.id);
    end if;
  end if;
  return new;
end;
$$;

-- Backfill every existing real account, oldest first so the earliest account
-- keeps the plain name on a collision.
do $$
declare
  r record;
begin
  for r in
    select id from public.profiles
     where username is null and not is_guest and deleted_at is null
     order by created_at, id
  loop
    perform private.assign_username(r.id);
  end loop;
end $$;

-- ---------------------------------------------------------------------- RPC --

create function public.username_available(p_username text)
returns boolean
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  v_me uuid := auth.uid();
begin
  if v_me is null then
    raise exception 'not_authenticated' using errcode = '28000';
  end if;
  if exists (select 1 from public.profiles where id = v_me and is_guest) then
    raise exception 'guests_cannot_have_username' using errcode = '42501';
  end if;
  perform private.rate_limit_hit('username_available', 60, interval '1 minute');

  if p_username is null or p_username !~ '^[A-Za-z0-9_]{3,20}$' or private.username_reserved(p_username) then
    return false;
  end if;
  return not exists (
    select 1 from public.profiles
     where lower(username) = lower(p_username) and id <> v_me
  );
end;
$$;

-- Sets the caller's username and returns it as stored. Errors:
--   invalid_username / username_reserved (22023), username_taken (23505),
--   guests_cannot_have_username (42501), rate_limited (54000).
create function public.claim_username(p_username text)
returns text
language plpgsql
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
    raise exception 'guests_cannot_have_username' using errcode = '42501';
  end if;

  if p_username is null or p_username !~ '^[A-Za-z0-9_]{3,20}$' then
    raise exception 'invalid_username' using errcode = '22023';
  end if;
  if private.username_reserved(p_username) then
    raise exception 'username_reserved' using errcode = '22023';
  end if;

  -- Counted on success only (a raise below rolls the increment back), which
  -- is the case that matters: it caps how often a name can be changed.
  perform private.rate_limit_hit('claim_username', 10, interval '1 hour');

  begin
    update public.profiles set username = p_username where id = v_me;
  exception when unique_violation then
    raise exception 'username_taken' using errcode = '23505';
  end;
  return p_username;
end;
$$;

revoke all on function public.username_available(text) from public, anon;
revoke all on function public.claim_username(text) from public, anon;
grant execute on function public.username_available(text) to authenticated;
grant execute on function public.claim_username(text) to authenticated;

-- ------------------------------------------------------ lock direct writes --
-- profiles_update_own lets a player UPDATE any column of their own row, which
-- would let a client write a username (or flip deleted_at) around the RPCs.
-- Clients only ever write display_name and avatar_url directly; everything
-- else is owned by SQL.
revoke update on public.profiles from authenticated;
grant update (display_name, avatar_url) on public.profiles to authenticated;

-- A deleted account releases its username.
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

  update auth.users
     set banned_until = now() + interval '100 years'
   where id = v_user;
end;
$$;
