-- A start countdown owned by the server.
--
-- Until now the 3-2-1 before a room game was a client-side overlay played on
-- top of a match whose first clock was already running: the auction's first lot
-- preview, for one, was mostly gone before anyone saw it, every client counted
-- from whenever its own board loaded, and a player who joined mid-countdown got
-- none.
--
-- Now a group match carries `play_starts_at`, three seconds after the host
-- starts it, and every deadline the game set on its way in is pushed back by the
-- same three seconds, so the first phase is full-length once the countdown ends.
-- Clients read the time with `match_play_start` and count down to it against the
-- server's clock, which is the same for everyone and survives a rejoin.
--
-- Solo runs have no countdown (`play_starts_at` stays null).

alter table public.matches add column play_starts_at timestamptz;

-- ------------------------------------------------------------------ helper --

create function private.match_start_lead()
returns interval
language sql immutable set search_path = ''
as $$ select interval '3 seconds' $$;

-- Marks the match's start and shifts the game's own deadlines to match. Called
-- by each game's `start` (and by the replay branch of `choose_post_game`) as the
-- last thing it does, so the deadlines it shifts are the ones it just set.
-- Mirrors `resume_match`, which shifts the same columns by the time spent paused.
create function private.begin_match_countdown(p_match_id uuid)
returns void
language plpgsql security definer set search_path = ''
as $$
declare
  v_game text;
  v_mode public.run_mode;
  v_lead interval := private.match_start_lead();
begin
  select m.game, r.mode into v_game, v_mode
    from public.matches m join public.runs r on r.id = m.run_id
   where m.id = p_match_id;
  if v_mode is distinct from 'arcade'::public.run_mode then return; end if;

  update public.matches set play_starts_at = now() + v_lead where id = p_match_id;

  case v_game
    when 'auction_team_builder' then
      update public.auction_matches
         set turn_deadline = turn_deadline + v_lead, phase_deadline = phase_deadline + v_lead
       where match_id = p_match_id;
    when 'higher_or_lower' then
      update public.higher_or_lower_matches
         set phase_deadline = phase_deadline + v_lead
       where match_id = p_match_id;
    when 'sabotage_draft' then
      update public.sabotage_draft_matches
         set turn_deadline = turn_deadline + v_lead
       where match_id = p_match_id;
    when 'wavelength_2v2' then
      update public.wavelength_matches
         set phase_deadline = phase_deadline + v_lead, phase_started_at = phase_started_at + v_lead
       where match_id = p_match_id;
    else null;
  end case;
end;
$$;

revoke all on function private.match_start_lead() from public, anon, authenticated;
revoke all on function private.begin_match_countdown(uuid) from public, anon, authenticated;

-- --------------------------------------------------------------------- read --

-- When play begins, and the server's clock, so a client can count down without
-- trusting its own. `play_starts_at` is null when there is nothing to wait for.
create function public.match_play_start(p_match_id uuid)
returns jsonb
language plpgsql stable security definer set search_path = ''
as $$
declare
  v_user uuid := auth.uid();
  v_at timestamptz;
begin
  if v_user is null then raise exception 'not_authenticated' using errcode = '42501'; end if;
  select m.play_starts_at into v_at
    from public.matches m
    join public.run_participants p on p.run_id = m.run_id and p.user_id = v_user
   where m.id = p_match_id;
  if not found then raise exception 'not_a_participant' using errcode = '42501'; end if;
  return jsonb_build_object('play_starts_at', v_at, 'server_now', now());
end;
$$;

revoke all on function public.match_play_start(uuid) from public, anon;
grant execute on function public.match_play_start(uuid) to authenticated;

-- ------------------------------------------------------------ the start paths --

CREATE OR REPLACE FUNCTION auction.start(p_match_id uuid, p_scoring_mode text, p_roster_preset text, p_season_from smallint DEFAULT NULL::smallint, p_season_to smallint DEFAULT NULL::smallint, p_token_count smallint DEFAULT NULL::smallint)
 RETURNS auction.turn
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare v_user uuid := auth.uid(); v_match public.matches;
begin
  if v_user is null then raise exception 'not_authenticated' using errcode = '42501'; end if;
  if p_scoring_mode is distinct from 'weekly' and p_scoring_mode is distinct from 'season_total' then raise exception 'invalid_scoring_mode' using errcode = 'P0001'; end if;
  if p_roster_preset is distinct from 'standard' and p_roster_preset is distinct from 'full' and p_roster_preset is distinct from 'deep' then raise exception 'invalid_roster_preset' using errcode = 'P0001'; end if;
  if p_token_count is not null and (p_token_count < 0 or p_token_count > 3) then raise exception 'invalid_token_count' using errcode = 'P0001'; end if;
  perform auction_private.resolve_season_range(p_season_from, p_season_to);
  select * into v_match from public.matches where id = p_match_id for update;
  if not found then raise exception 'match_not_found' using errcode = 'P0001'; end if;
  if v_match.game <> 'auction_team_builder' then raise exception 'wrong_game' using errcode = 'P0001'; end if;
  if not exists (select 1 from public.run_participants where run_id = v_match.run_id and user_id = v_user) then raise exception 'not_a_participant' using errcode = '42501'; end if;
  if v_match.status <> 'setup'::public.match_status then raise exception 'match_not_setup' using errcode = 'P0001'; end if;
  perform auction_private.deal_board(p_match_id, null, p_scoring_mode, p_roster_preset, p_season_from, p_season_to, p_token_count);
  update public.matches set status = 'playing'::public.match_status, started_at = now() where id = p_match_id;
  perform auction_private.advance(p_match_id); perform private.begin_match_countdown(p_match_id); return auction_private.turn_of(p_match_id);
end;
$function$;

CREATE OR REPLACE FUNCTION higher_or_lower.start(p_match_id uuid, p_scoring_mode text DEFAULT 'season_total'::text, p_season_from smallint DEFAULT NULL::smallint, p_season_to smallint DEFAULT NULL::smallint)
 RETURNS higher_or_lower.board
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare v_user uuid := auth.uid(); v_match public.matches;
begin
  if v_user is null then raise exception 'not_authenticated' using errcode = '42501'; end if;
  if p_scoring_mode not in ('weekly', 'season_total') then raise exception 'invalid_scoring_mode' using errcode = 'P0001'; end if;
  perform higher_or_lower_private.resolve_season_range(p_season_from, p_season_to);
  select * into v_match from public.matches where id = p_match_id for update;
  if not found then raise exception 'match_not_found' using errcode = 'P0001'; end if;
  if v_match.game <> 'higher_or_lower' then raise exception 'wrong_game' using errcode = 'P0001'; end if;
  if not exists (select 1 from public.run_participants where run_id = v_match.run_id and user_id = v_user) then raise exception 'not_a_participant' using errcode = '42501'; end if;
  if v_match.status <> 'setup'::public.match_status then raise exception 'match_not_setup' using errcode = 'P0001'; end if;
  perform higher_or_lower_private.deal_board(p_match_id, null, p_scoring_mode, p_season_from, p_season_to);
  update public.matches set status = 'playing', started_at = now() where id = p_match_id;
  update public.higher_or_lower_matches
     set phase = 'board_intro', phase_deadline = now() + interval '5 seconds'
   where match_id = p_match_id and not is_solo;
  perform private.begin_match_countdown(p_match_id);
  return higher_or_lower_private.board_of(p_match_id);
end;
$function$;

CREATE OR REPLACE FUNCTION sabotage_draft.start(p_match_id uuid, p_mode text DEFAULT 'full'::text)
 RETURNS sabotage_draft.round
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_user  uuid := auth.uid();
  v_match public.matches;
begin
  if v_user is null then
    raise exception 'not_authenticated' using errcode = '42501';
  end if;

  if p_mode is null or p_mode not in ('full', 'standard', 'quick') then
    raise exception 'invalid_mode' using errcode = '22023';
  end if;

  -- The lock is what makes "deal twice" impossible rather than unlikely.
  select * into v_match from public.matches where id = p_match_id for update;
  if not found then
    raise exception 'match_not_found' using errcode = 'P0001';
  end if;

  if v_match.game <> 'sabotage_draft' then
    raise exception 'wrong_game' using errcode = 'P0001';
  end if;

  if not exists (
    select 1 from public.run_participants
     where run_id = v_match.run_id and user_id = v_user
  ) then
    raise exception 'not_a_participant' using errcode = '42501';
  end if;

  if v_match.status <> 'setup'::public.match_status then
    raise exception 'match_not_setup' using errcode = 'P0001';
  end if;

  perform sabotage_draft_private.deal_board(p_match_id, null, p_mode);

  update public.matches
     set status = 'playing'::public.match_status,
         started_at = now()
   where id = p_match_id;

  perform private.begin_match_countdown(p_match_id);

  return sabotage_draft_private.round_of(p_match_id);
end;
$function$;

CREATE OR REPLACE FUNCTION wavelength.start(p_match_id uuid, p_mode text, p_preset text DEFAULT NULL::text)
 RETURNS wavelength.board
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_user  uuid := auth.uid();
  v_match public.matches;
begin
  if v_user is null then
    raise exception 'not_authenticated' using errcode = '42501';
  end if;

  -- The lock is what makes "deal twice" impossible rather than unlikely.
  select * into v_match from public.matches where id = p_match_id for update;
  if not found then
    raise exception 'match_not_found' using errcode = 'P0001';
  end if;

  if v_match.game <> 'wavelength_2v2' then
    raise exception 'wrong_game' using errcode = 'P0001';
  end if;

  if not exists (
    select 1 from public.run_participants
     where run_id = v_match.run_id and user_id = v_user
  ) then
    raise exception 'not_a_participant' using errcode = '42501';
  end if;

  if v_match.status <> 'setup'::public.match_status then
    raise exception 'match_not_setup' using errcode = 'P0001';
  end if;

  perform wavelength_private.deal_board(p_match_id, p_mode, p_preset, null);

  update public.matches
     set status = 'playing'::public.match_status,
         started_at = now()
   where id = p_match_id;

  perform private.begin_match_countdown(p_match_id);

  return wavelength_private.board_of(p_match_id);
end;
$function$;

CREATE OR REPLACE FUNCTION public.choose_post_game(p_match_id uuid, p_choice post_game_choice, p_scoring_mode text DEFAULT NULL::text, p_roster_preset text DEFAULT NULL::text, p_season_from smallint DEFAULT NULL::smallint, p_season_to smallint DEFAULT NULL::smallint)
 RETURNS post_game_actions
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_user uuid := auth.uid();
  v_match public.matches;
  v_run public.runs;
  v_lobby public.lobbies;
  v_format public.auction_matches;
  v_hol public.higher_or_lower_matches;
  v_wavelength public.wavelength_matches;
  v_next_run public.runs;
  v_next_match public.matches;
  v_action public.post_game_actions;
  v_scoring_mode text;
  v_roster_preset text;
  v_season_from smallint;
  v_season_to smallint;
begin
  if v_user is null then raise exception 'not_authenticated' using errcode = '42501'; end if;

  select * into v_match from public.matches where id = p_match_id;
  if not found then raise exception 'match_not_found' using errcode = 'P0001'; end if;
  select * into v_run from public.runs where id = v_match.run_id;
  if v_run.lobby_id is null then
    if not exists (select 1 from public.run_participants where run_id = v_run.id and user_id = v_user) then
      raise exception 'not_match_participant' using errcode = '42501';
    end if;
  else
    select * into v_lobby from public.lobbies where id = v_run.lobby_id for update;
    if v_lobby.host_id <> v_user then raise exception 'not_host' using errcode = '42501'; end if;
  end if;

  if v_match.status <> 'complete'::public.match_status then raise exception 'match_not_complete' using errcode = 'P0001'; end if;
  if exists (select 1 from public.post_game_actions where match_id = p_match_id) then raise exception 'post_game_choice_already_made' using errcode = 'P0001'; end if;

  if p_choice = 'replay'::public.post_game_choice then
    if v_match.game = 'auction_team_builder' then
      select * into v_format from public.auction_matches where match_id = p_match_id;
      if not found or v_format.scoring_mode is null or v_format.roster_preset is null then raise exception 'replay_not_supported' using errcode = 'P0001'; end if;
      v_scoring_mode := coalesce(p_scoring_mode, v_format.scoring_mode);
      v_roster_preset := coalesce(p_roster_preset, v_format.roster_preset);
      v_season_from := coalesce(p_season_from, v_format.season_from);
      v_season_to := coalesce(p_season_to, v_format.season_to);
      if v_scoring_mode not in ('weekly', 'season_total') then raise exception 'invalid_scoring_mode' using errcode = 'P0001'; end if;
      if v_roster_preset not in ('standard', 'full', 'deep') then raise exception 'invalid_roster_preset' using errcode = 'P0001'; end if;
      perform auction_private.resolve_season_range(v_season_from, v_season_to);

      insert into public.runs (lobby_id, mode) values (case when v_run.lobby_id is null then null else v_lobby.id end, case when v_run.lobby_id is null then 'solo'::public.run_mode else 'arcade'::public.run_mode end) returning * into v_next_run;
      insert into public.run_participants (run_id, user_id, seat) select v_next_run.id, user_id, seat from public.run_participants where run_id = v_run.id;
      insert into public.matches (run_id, game, seq, status) values (v_next_run.id, v_match.game, 1, 'setup'::public.match_status) returning * into v_next_match;
      perform auction_private.deal_board(v_next_match.id, null, v_scoring_mode, v_roster_preset, v_season_from, v_season_to);
      update public.matches set status = 'playing'::public.match_status, started_at = now() where id = v_next_match.id;
      perform auction_private.advance(v_next_match.id);
      perform private.begin_match_countdown(v_next_match.id);

    elsif v_match.game = 'higher_or_lower' then
      select * into v_hol from public.higher_or_lower_matches where match_id = p_match_id;
      if not found then raise exception 'replay_not_supported' using errcode = 'P0001'; end if;
      v_season_from := coalesce(p_season_from, v_hol.season_from);
      v_season_to := coalesce(p_season_to, v_hol.season_to);
      insert into public.runs (lobby_id, mode) values (case when v_run.lobby_id is null then null else v_lobby.id end, case when v_run.lobby_id is null then 'solo'::public.run_mode else 'arcade'::public.run_mode end) returning * into v_next_run;
      insert into public.run_participants (run_id, user_id, seat) select v_next_run.id, user_id, seat from public.run_participants where run_id = v_run.id;
      insert into public.matches (run_id, game, seq, status) values (v_next_run.id, v_match.game, 1, 'setup'::public.match_status) returning * into v_next_match;
      perform higher_or_lower_private.deal_board(v_next_match.id, null, v_hol.scoring_mode, v_season_from, v_season_to);
      update public.matches set status = 'playing'::public.match_status, started_at = now() where id = v_next_match.id;
      update public.higher_or_lower_matches set phase = 'board_intro', phase_deadline = now() + interval '5 seconds' where match_id = v_next_match.id and not is_solo;
      perform private.begin_match_countdown(v_next_match.id);

    elsif v_match.game = 'wavelength_2v2' then
      select * into v_wavelength from public.wavelength_matches where match_id = p_match_id;
      if not found then raise exception 'replay_not_supported' using errcode = 'P0001'; end if;
      insert into public.runs (lobby_id, mode) values (v_lobby.id, 'arcade'::public.run_mode) returning * into v_next_run;
      insert into public.run_participants (run_id, user_id, seat) select v_next_run.id, user_id, seat from public.run_participants where run_id = v_run.id;
      insert into public.matches (run_id, game, seq, status) values (v_next_run.id, v_match.game, 1, 'setup'::public.match_status) returning * into v_next_match;
      perform wavelength_private.deal_board(v_next_match.id, v_wavelength.mode, v_wavelength.preset, null);
      update public.matches set status = 'playing'::public.match_status, started_at = now() where id = v_next_match.id;
      perform private.begin_match_countdown(v_next_match.id);

    else
      raise exception 'replay_not_supported' using errcode = 'P0001';
    end if;
    insert into public.post_game_actions (match_id, choice, next_match_id) values (p_match_id, p_choice, v_next_match.id) returning * into v_action;
  else
    insert into public.post_game_actions (match_id, choice) values (p_match_id, p_choice) returning * into v_action;
  end if;
  return v_action;
end;
$function$;
