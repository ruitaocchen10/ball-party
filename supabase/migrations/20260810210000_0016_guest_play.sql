-- Guests are ordinary auth users without credentials.  This migration widens
-- the existing player surface to anonymous sessions, while deliberately
-- retaining the two product boundaries: only credentialed users create rooms
-- and start runs.

alter table public.profiles
  add column is_guest boolean not null default false;

update public.profiles p
   set is_guest = coalesce(u.is_anonymous, false)
  from auth.users u
 where u.id = p.id;

-- The profile is the roster's public projection of identity.  It needs only
-- this one fact from auth.users so co-players can see that a seat is a guest.
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
    new.raw_user_meta_data ->> 'avatar_url',
    coalesce(new.is_anonymous, false)
  )
  on conflict (id) do nothing;
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
  end if;
  return new;
end;
$$;

create trigger on_auth_user_guest_status_changed
  after update of is_anonymous on auth.users
  for each row execute function private.sync_guest_profile();

-- Both profile policies were product gates, not identity protections.  A guest
-- is a player, so they may read their own profile and their co-players' names.
drop policy profiles_select_own on public.profiles;
create policy profiles_select_own on public.profiles
  for select to authenticated using (auth.uid() = id);

create function private.is_guest_user(p_user_id uuid)
returns boolean
language sql security definer set search_path = '' stable
as $$
  select coalesce((select is_anonymous from auth.users where id = p_user_id), false);
$$;

drop policy profiles_update_own on public.profiles;
create policy profiles_update_own on public.profiles
  for update to authenticated
  using (auth.uid() = id)
  with check (auth.uid() = id and is_guest = private.is_guest_user(id));

drop policy profiles_select_co_player on public.profiles;
create policy profiles_select_co_player on public.profiles
  for select to authenticated using (private.shares_lobby_with(id));

-- A guest can enter a room, but cannot make one.  The run-start boundary stays
-- below untouched: the host is always a credentialed account today.
create or replace function public.join_lobby(p_code text)
returns public.lobbies
language plpgsql security definer set search_path = ''
as $$
declare
  v_user   uuid := auth.uid();
  v_code   text := upper(trim(coalesce(p_code, '')));
  v_lobby  public.lobbies;
  v_others int;
begin
  if v_user is null then
    raise exception 'not_authenticated' using errcode = '42501';
  end if;

  select * into v_lobby from public.lobbies
   where code = v_code and closed_at is null for update;
  if not found then raise exception 'lobby_not_found' using errcode = 'P0001'; end if;

  if exists (
    select 1 from public.lobby_members
     where lobby_id = v_lobby.id and user_id = v_user and left_at is null
  ) then return v_lobby; end if;

  select count(*) into v_others from public.lobby_members
   where lobby_id = v_lobby.id and user_id <> v_user and left_at is null;
  if v_others >= 4 then raise exception 'lobby_full' using errcode = 'P0001'; end if;

  perform private.leave_all_lobbies(v_user);
  insert into public.lobby_members (lobby_id, user_id) values (v_lobby.id, v_user)
  on conflict (lobby_id, user_id) do update set left_at = null;
  return v_lobby;
end;
$$;

-- These are the current auction write entry points.  The game-native
-- participant and turn checks remain; only the credential requirement goes.
create or replace function public.start_auction(p_match_id uuid)
returns public.auction_turn
language plpgsql security definer set search_path = ''
as $$
declare v_user uuid := auth.uid(); v_match public.matches;
begin
  if v_user is null then raise exception 'not_authenticated' using errcode = '42501'; end if;
  select * into v_match from public.matches where id = p_match_id for update;
  if not found then raise exception 'match_not_found' using errcode = 'P0001'; end if;
  if v_match.game <> 'auction_team_builder' then raise exception 'wrong_game' using errcode = 'P0001'; end if;
  if not exists (select 1 from public.run_participants where run_id = v_match.run_id and user_id = v_user) then
    raise exception 'not_a_participant' using errcode = '42501';
  end if;
  if v_match.status <> 'setup'::public.match_status then raise exception 'match_not_setup' using errcode = 'P0001'; end if;
  perform private.deal_auction_board(p_match_id);
  update public.matches set status = 'playing'::public.match_status, started_at = now() where id = p_match_id;
  perform private.auction_advance(p_match_id);
  return private.auction_turn_of(p_match_id);
end;
$$;

create or replace function public.place_bid(p_match_id uuid, p_amount numeric)
returns public.auction_turn
language plpgsql security definer set search_path = ''
as $$
declare v_user uuid := auth.uid();
begin
  if v_user is null then raise exception 'not_authenticated' using errcode = '42501'; end if;
  perform private.auction_apply(p_match_id, v_user, 'raise', p_amount, false);
  return private.auction_turn_of(p_match_id);
end;
$$;

create or replace function public.pass_lot(p_match_id uuid)
returns public.auction_turn
language plpgsql security definer set search_path = ''
as $$
declare v_user uuid := auth.uid();
begin
  if v_user is null then raise exception 'not_authenticated' using errcode = '42501'; end if;
  perform private.auction_apply(p_match_id, v_user, 'pass', null, false);
  return private.auction_turn_of(p_match_id);
end;
$$;

create or replace function public.expire_turn(p_match_id uuid)
returns public.auction_turn
language plpgsql security definer set search_path = ''
as $$
declare v_user uuid := auth.uid();
begin
  if v_user is null then raise exception 'not_authenticated' using errcode = '42501'; end if;
  if not exists (select 1 from public.auction_players where match_id = p_match_id and user_id = v_user) then
    raise exception 'not_a_participant' using errcode = '42501';
  end if;
  perform private.auction_expire(p_match_id);
  return private.auction_turn_of(p_match_id);
end;
$$;

create table public.guest_account_collisions (
  guest_id uuid primary key references public.profiles(id) on delete cascade,
  account_id uuid not null references public.profiles(id),
  created_at timestamptz not null default now(),
  check (guest_id <> account_id)
);

alter table public.guest_account_collisions enable row level security;

create function public.record_guest_account_collision(p_guest_id uuid)
returns void
language plpgsql security definer set search_path = ''
as $$
begin
  if auth.uid() is null or auth.uid() = p_guest_id then
    raise exception 'not_authenticated' using errcode = '42501';
  end if;
  if not exists (select 1 from auth.users where id = p_guest_id and is_anonymous) then
    raise exception 'not_a_guest' using errcode = '42501';
  end if;
  insert into public.guest_account_collisions (guest_id, account_id)
  values (p_guest_id, auth.uid())
  on conflict (guest_id) do update set account_id = excluded.account_id, created_at = excluded.created_at;
end;
$$;

create function private.cleanup_guest_accounts()
returns void
language sql security definer set search_path = ''
as $$
  delete from auth.users u
   where u.is_anonymous
     and u.created_at < now() - interval '30 days'
     and not exists (select 1 from public.run_participants rp where rp.user_id = u.id);
$$;

select cron.schedule('guest-account-cleanup', '0 3 * * *', $$ select private.cleanup_guest_accounts() $$);

revoke all on function private.sync_guest_profile() from public, anon, authenticated;
revoke all on function private.cleanup_guest_accounts() from public, anon, authenticated;
revoke all on function private.is_guest_user(uuid) from public, anon;
revoke all on function public.record_guest_account_collision(uuid) from public, anon;
grant execute on function private.is_guest_user(uuid) to authenticated;
grant execute on function public.record_guest_account_collision(uuid) to authenticated;
