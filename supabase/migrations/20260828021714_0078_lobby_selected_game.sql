-- The room's own "next up" state.
--
-- Until now, picking a game and starting it were the same tap: `startRun`
-- (0009) both dispatches the game and freezes the roster in one call. The
-- lobby UI is moving to a two-step flow — the host chooses a game, everyone
-- sees that choice, and starting it is a second, separate action — which
-- needs somewhere durable to hold "chosen but not yet started" between those
-- two steps. `lobbies` already has no notion of an active game (see 0009's
-- own header: "The lobby has no mode. Mode is chosen per run"), so this adds
-- exactly one column for it rather than reopening that design.
--
-- The check constraint mirrors `matches.game`'s value list (0009) rather than
-- being derived from it, the same trade-off 0009 already made for that column:
-- Postgres has no way to share a literal list between two check constraints,
-- and a foreign key to a lookup table would be new machinery for five names
-- that change on the order of once a quarter.
alter table public.lobbies
  add column selected_game text
    check (selected_game in (
      'auction_team_builder',
      'cards_against_humanity',
      'higher_or_lower',
      'wavelength_2v2',
      'sabotage_draft'
    ));

-- The write side. Mirrors public.start_run's own guard sequence (auth, lobby
-- exists and is open, caller is host, caller is still a member) because this
-- is the same "may this person steer the room" question start_run already
-- answers — a lock, not a rewrite of it, since selecting a game does not
-- touch runs or matches at all.
create function public.select_lobby_game(p_lobby_id uuid, p_game text)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_user  uuid := auth.uid();
  v_lobby public.lobbies;
begin
  if v_user is null or (auth.jwt() ->> 'is_anonymous')::boolean is true then
    raise exception 'not_authenticated' using errcode = '42501';
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

  -- A choice made while a match is already running is not a bug — the host is
  -- picking what plays next, same as landing on an already-selected game does
  -- today — so this is deliberately not guarded on runs_one_active.

  update public.lobbies set selected_game = p_game where id = p_lobby_id;
end;
$$;

revoke all on function public.select_lobby_game(uuid, text) from public, anon;
grant execute on function public.select_lobby_game(uuid, text) to authenticated;
