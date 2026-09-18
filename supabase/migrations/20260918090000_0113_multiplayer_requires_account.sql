-- Web-side companion to the iOS spec (issue #59): multiplayer requires a real
-- account. iOS never carries a guest session at all, so the two clients only
-- stay consistent if the web RPCs refuse one too.
--
-- `start_run` (0009) and `select_lobby_game` (0078) already refused a guest,
-- collapsed into the same 'not_authenticated' raised for no session at all.
-- `join_lobby` was the one gap: 0016 deliberately widened it to let a guest
-- into a room, back when guests were meant to play multiplayer matches.
-- Closing it here is what actually blocks a guest from multiplayer, since a
-- player who can never join a room can never reach the two guards above
-- either — start_run and select_lobby_game only matter to a room's members.
--
-- The one hole that leaves: a guest already seated from before this
-- migration shipped. That membership isn't retroactively removed, and
-- start_run seats every current member, not just its caller — so a real
-- host calling start_run could still carry a grandfathered guest straight
-- into a match. start_run's added check closes that directly, by refusing
-- to start if any current member is a guest, rather than relying on
-- join_lobby alone.
--
-- All three now raise a distinct 'account_required' for "signed in, but a
-- guest" rather than folding it into 'not_authenticated'. A guest already has
-- a working session; telling them to sign in again is the confusing error the
-- product spec calls out. A caller with no session at all still gets
-- 'not_authenticated', unchanged.
--
-- Solo is untouched: `start_solo_run` (0044) never gated on is_anonymous and
-- still doesn't. Guest play as a whole is not going away, only its multiplayer
-- half.

create or replace function public.join_lobby(p_code text)
returns public.lobbies
language plpgsql
security definer
set search_path = ''
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
  if (auth.jwt() ->> 'is_anonymous')::boolean is true then
    raise exception 'account_required' using errcode = '42501';
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

create or replace function public.select_lobby_game(p_lobby_id uuid, p_game text)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_user  uuid := auth.uid();
  v_lobby public.lobbies;
begin
  if v_user is null then
    raise exception 'not_authenticated' using errcode = '42501';
  end if;
  if (auth.jwt() ->> 'is_anonymous')::boolean is true then
    raise exception 'account_required' using errcode = '42501';
  end if;

  select * into v_lobby from public.lobbies where id = p_lobby_id for update;
  if not found then
    raise exception 'lobby_not_found' using errcode = 'P0001';
  end if;

  if v_lobby.closed_at is not null then
    raise exception 'lobby_closed' using errcode = 'P0001';
  end if;

  if v_lobby.host_id <> v_user then
    raise exception 'not_host' using errcode = '42501';
  end if;

  if not exists (
    select 1 from public.lobby_members
     where lobby_id = p_lobby_id and user_id = v_user and left_at is null
  ) then
    raise exception 'not_a_member' using errcode = '42501';
  end if;

  update public.lobbies set selected_game = p_game where id = p_lobby_id;
end;
$$;

create or replace function public.start_run(p_lobby_id uuid, p_mode public.run_mode, p_game text)
returns public.matches
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_user  uuid := auth.uid();
  v_lobby public.lobbies;
  v_count int;
  v_run   public.runs;
  v_match public.matches;
begin
  if v_user is null then
    raise exception 'not_authenticated' using errcode = '42501';
  end if;
  if (auth.jwt() ->> 'is_anonymous')::boolean is true then
    raise exception 'account_required' using errcode = '42501';
  end if;

  select * into v_lobby from public.lobbies where id = p_lobby_id for update;
  if not found then
    raise exception 'lobby_not_found' using errcode = 'P0001';
  end if;

  if v_lobby.closed_at is not null then
    raise exception 'lobby_closed' using errcode = 'P0001';
  end if;

  if v_lobby.host_id <> v_user then
    raise exception 'not_host' using errcode = '42501';
  end if;

  if not exists (
    select 1 from public.lobby_members
     where lobby_id = p_lobby_id and user_id = v_user and left_at is null
  ) then
    raise exception 'not_a_member' using errcode = '42501';
  end if;

  -- join_lobby refuses a guest now, but a room can still hold one seated
  -- before this migration shipped. start_run seats every current member
  -- (below), so that grandfathered guest would otherwise ride a real host's
  -- call straight into a match — the one path 0113's own header comment
  -- assumed was already closed by join_lobby alone.
  if exists (
    select 1 from public.lobby_members lm
      join public.profiles p on p.id = lm.user_id
     where lm.lobby_id = p_lobby_id and lm.left_at is null and p.is_guest
  ) then
    raise exception 'account_required' using errcode = '42501';
  end if;

  select count(*) into v_count
    from public.lobby_members
   where lobby_id = p_lobby_id and left_at is null;

  if v_count < 2 or v_count > 4 then
    raise exception 'bad_player_count' using errcode = 'P0001';
  end if;

  if p_mode <> 'arcade'::public.run_mode then
    raise exception 'mode_not_supported' using errcode = 'P0001';
  end if;

  begin
    insert into public.runs (lobby_id, mode)
    values (p_lobby_id, p_mode)
    returning * into v_run;
  exception when unique_violation then
    raise exception 'run_already_active' using errcode = 'P0001';
  end;

  insert into public.run_participants (run_id, user_id, seat)
  select v_run.id, s.user_id, (row_number() over (order by s.ord) - 1)::smallint
    from (
      select user_id, random() as ord
        from public.lobby_members
       where lobby_id = p_lobby_id and left_at is null
    ) s;

  insert into public.matches (run_id, game, seq, status)
  values (v_run.id, p_game, 1, 'setup'::public.match_status)
  returning * into v_match;

  return v_match;
end;
$$;
