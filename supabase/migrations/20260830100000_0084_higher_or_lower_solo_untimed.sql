-- Solo Higher or Lower drops every clock. A solo ladder already has no
-- opponent to keep pace with, so the 12-second call countdown and the
-- automatic reveal-to-next-question pause were pressure with nobody to apply
-- it to. Solo now runs entirely on the player's own taps: call whenever
-- ready, then tap to see the next card. The endless ladder (0046) already
-- keeps going until a call is wrong; the fixed twelve-question framing this
-- removes was only ever visual (see the `is solo` guards on the label
-- itself, in the frontend).
--
-- Group play is untouched: it keeps the pacing that gives every seat at the
-- table the same clock.

-- ------------------------------------------------------------- open/reveal --

-- A solo board never times a call out from under its only player.
create or replace function higher_or_lower_private.open_question(
  p_match_id uuid,
  p_question smallint
)
returns void
language sql
security definer
set search_path = ''
as $$
  update public.higher_or_lower_matches
     set current_question    = p_question,
         phase                = 'call',
         phase_deadline       = case when is_solo then null else now() + interval '12 seconds' end,
         question_started_at  = now()
   where match_id = p_match_id;
$$;

-- A solo board never auto-advances out of a reveal either: the player reads
-- the card on their own clock and taps `higher_or_lower.advance` when ready.
create or replace function higher_or_lower_private.reveal_question(
  p_match_id uuid,
  p_question smallint
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare v_opened timestamptz;
begin
  select question_started_at into v_opened
    from public.higher_or_lower_matches where match_id = p_match_id;

  update public.higher_or_lower_cards c
     set points = a.points, revealed_at = now()
    from higher_or_lower_private.answers a
   where c.match_id = p_match_id
     and c.ordinal = p_question
     and a.match_id = c.match_id
     and a.ordinal = c.ordinal;

  insert into public.higher_or_lower_calls (match_id, question, user_id, direction, timed_out)
  select p_match_id, p_question, p.user_id, null, true
    from public.higher_or_lower_players p
   where p.match_id = p_match_id
     and not exists (
       select 1 from public.higher_or_lower_calls c
        where c.match_id = p_match_id and c.question = p_question and c.user_id = p.user_id
     );

  perform higher_or_lower_private.score_question(p_match_id, p_question);

  update public.higher_or_lower_players p
     set absent = true
   where p.match_id = p_match_id
     and not p.absent
     and v_opened is not null
     and p.last_seen_at < v_opened;

  update public.higher_or_lower_matches
     set phase = 'reveal',
         phase_deadline = case when is_solo then null else now() + interval '4 seconds' end
   where match_id = p_match_id;
end;
$$;

-- --------------------------------------------------------------- the deal --

-- A solo deal skips the board-intro clock entirely rather than dealing it
-- and immediately racing to disarm it: it opens straight into an untimed
-- first question, which `open_question` above already knows how to give it.
create or replace function higher_or_lower_private.deal_board(
  p_match_id uuid,
  p_seed double precision default null,
  p_scoring_mode text default 'season_total',
  p_season_from smallint default null,
  p_season_to smallint default null
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_seed double precision := coalesce(p_seed, random());
  v_question_count constant smallint := 12;
  v_spare_count constant smallint := 5;
  v_from smallint;
  v_to smallint;
  v_n int;
  v_i smallint;
  v_last_ordinal smallint;
  v_solo boolean;
begin
  if p_scoring_mode not in ('weekly', 'season_total') then
    raise exception 'invalid_scoring_mode' using errcode = 'P0001';
  end if;
  select r.season_from, r.season_to into v_from, v_to
    from higher_or_lower_private.resolve_season_range(p_season_from, p_season_to) r;

  insert into public.higher_or_lower_players (match_id, user_id, seat)
  select p_match_id, rp.user_id, rp.seat
    from public.run_participants rp join public.matches m on m.run_id = rp.run_id
   where m.id = p_match_id;
  select count(*) into v_n from public.higher_or_lower_players where match_id = p_match_id;
  if v_n < 1 then raise exception 'too_few_players' using errcode = 'P0001'; end if;
  v_solo := v_n = 1;

  insert into public.higher_or_lower_matches (
    match_id, question_count, spare_count, current_question,
    scoring_mode, season_from, season_to, is_solo
  ) values (
    p_match_id, v_question_count, v_spare_count, 1,
    p_scoring_mode, v_from, v_to, v_solo
  );
  insert into higher_or_lower_private.boards (match_id, seed) values (p_match_id, v_seed);

  perform setseed(v_seed);
  set local max_parallel_workers_per_gather = 0;
  perform higher_or_lower_private.prepare_deck(p_match_id);
  v_last_ordinal := case when v_solo then v_question_count else v_question_count + v_spare_count end;
  for v_i in 0 .. v_last_ordinal loop
    if not higher_or_lower_private.deal_next_card(p_match_id, v_i::smallint) then
      raise exception 'pool_exhausted' using errcode = 'P0001';
    end if;
  end loop;

  if v_solo then
    perform higher_or_lower_private.open_question(p_match_id, 1::smallint);
  end if;
end;
$$;

-- ------------------------------------------------------------------ start --

-- Unchanged for group play. A solo board already opened its first, untimed
-- question inside deal_board above, so this is a no-op for it.
create or replace function higher_or_lower.start(
  p_match_id uuid, p_scoring_mode text default 'season_total',
  p_season_from smallint default null, p_season_to smallint default null
) returns higher_or_lower.board
language plpgsql security definer set search_path = ''
as $$
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
  return higher_or_lower_private.board_of(p_match_id);
end;
$$;

-- -------------------------------------------------------------------- call --

-- A null deadline now means "no deadline" rather than "reject every call".
-- Only a group board, where `open_question` still stamps a real deadline,
-- can ever raise `call_deadline_passed` — solo has none left to stamp, since
-- sudden death (the other user of this deadline) never happens with one
-- player to tie against.
create or replace function higher_or_lower.call(p_match_id uuid, p_direction text)
returns public.higher_or_lower_calls
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_user uuid := auth.uid();
  v_board public.higher_or_lower_matches;
  v_player public.higher_or_lower_players;
  v_call public.higher_or_lower_calls;
begin
  if v_user is null then
    raise exception 'not_authenticated' using errcode = '42501';
  end if;
  if p_direction not in ('higher', 'lower') then
    raise exception 'invalid_direction' using errcode = 'P0001';
  end if;

  select hm.* into v_board
    from public.higher_or_lower_matches hm
    join public.matches mt on mt.id = hm.match_id
   where hm.match_id = p_match_id
     and mt.status = 'playing'::public.match_status
   for update of hm;
  if not found then raise exception 'match_not_playing' using errcode = 'P0001'; end if;

  select * into v_player
    from public.higher_or_lower_players
   where match_id = p_match_id and user_id = v_user;
  if not found then raise exception 'not_a_participant' using errcode = '42501'; end if;

  if v_board.phase not in ('call', 'sudden_death_call') then
    raise exception 'call_not_open' using errcode = 'P0001';
  end if;
  -- Everyone in the match may call in the main round. Once sudden death is
  -- live, only the tied leaders it admitted, and only while they are still
  -- alive in it — everyone else is watching a field already settled.
  if v_board.phase = 'sudden_death_call'
     and not (v_player.sudden_death and v_player.eliminated_at is null) then
    raise exception 'not_alive_in_sudden_death' using errcode = '42501';
  end if;
  if v_board.phase_deadline is not null and v_board.phase_deadline <= now() then
    raise exception 'call_deadline_passed' using errcode = 'P0001';
  end if;
  if higher_or_lower_private.has_called(p_match_id, v_board.current_question, v_user) then
    raise exception 'already_called' using errcode = 'P0001';
  end if;

  update public.higher_or_lower_players
     set last_seen_at = now(), absent = false
   where match_id = p_match_id and user_id = v_user;

  insert into public.higher_or_lower_calls (match_id, question, user_id, direction)
  values (p_match_id, v_board.current_question, v_user, p_direction)
  returning * into v_call;

  insert into public.higher_or_lower_call_statuses (match_id, question, user_id)
  values (p_match_id, v_board.current_question, v_user);

  if v_board.phase = 'sudden_death_call' then
    if not exists (
      select 1
        from public.higher_or_lower_players p
       where p.match_id = p_match_id
         and p.sudden_death
         and p.eliminated_at is null
         and not p.absent
         and not exists (
           select 1 from public.higher_or_lower_calls c
            where c.match_id = p_match_id
              and c.question = v_board.current_question
              and c.user_id = p.user_id
         )
    ) then
      perform higher_or_lower_private.reveal_sudden_death_round(p_match_id, v_board.current_question);
    end if;
  else
    if not exists (
      select 1
        from public.higher_or_lower_players p
       where p.match_id = p_match_id
         and not p.absent
         and not exists (
           select 1 from public.higher_or_lower_calls c
            where c.match_id = p_match_id
              and c.question = v_board.current_question
              and c.user_id = p.user_id
         )
    ) then
      perform higher_or_lower_private.reveal_question(p_match_id, v_board.current_question);
    end if;
  end if;

  return v_call;
end;
$$;

-- ----------------------------------------------------------------- advance --

-- Solo's replacement for the timer door in `expire`. It runs the same
-- decision expire's solo branch used to make on a schedule — complete on a
-- broken streak, otherwise open the next question, extending the ladder past
-- its pre-dealt twelve once that runs out — except a player asks for it
-- instead of a clock. Group boards keep the clock and have no use for this.
create function higher_or_lower.advance(p_match_id uuid)
returns higher_or_lower.board
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_user uuid := auth.uid();
  v_board public.higher_or_lower_matches;
begin
  if v_user is null then
    raise exception 'not_authenticated' using errcode = '42501';
  end if;

  select hm.* into v_board
    from public.higher_or_lower_matches hm
    join public.matches mt on mt.id = hm.match_id
   where hm.match_id = p_match_id
     and mt.status = 'playing'::public.match_status
   for update of hm;
  if not found then raise exception 'match_not_playing' using errcode = 'P0001'; end if;
  if not v_board.is_solo then raise exception 'not_solo' using errcode = 'P0001'; end if;
  if not exists (
    select 1 from public.higher_or_lower_players
     where match_id = p_match_id and user_id = v_user
  ) then raise exception 'not_a_participant' using errcode = '42501'; end if;
  if v_board.phase <> 'reveal' then raise exception 'advance_not_open' using errcode = 'P0001'; end if;

  if exists (
    select 1 from public.higher_or_lower_players
     where match_id = p_match_id and current_streak = 0
  ) then
    perform higher_or_lower_private.complete_match(p_match_id);
  elsif v_board.current_question < v_board.question_count then
    perform higher_or_lower_private.open_question(p_match_id, (v_board.current_question + 1)::smallint);
  elsif higher_or_lower_private.extend_board(p_match_id) then
    perform higher_or_lower_private.open_question(p_match_id, (v_board.current_question + 1)::smallint);
  else
    perform higher_or_lower_private.complete_match(p_match_id);
  end if;

  return higher_or_lower_private.board_of(p_match_id);
end;
$$;

revoke all on function higher_or_lower.advance(uuid) from public, anon;
grant execute on function higher_or_lower.advance(uuid) to authenticated;

-- ----------------------------------------------------------------- replay --

-- Solo replay goes through the same untimed path: deal_board already opens
-- an untimed first question for it, so the explicit board-intro clock below
-- is, like `start` above, only for the lobby-backed branch.
create or replace function public.choose_post_game(
  p_match_id uuid,
  p_choice public.post_game_choice,
  p_scoring_mode text default null,
  p_roster_preset text default null,
  p_season_from smallint default null,
  p_season_to smallint default null
)
returns public.post_game_actions
language plpgsql
security definer
set search_path to ''
as $$
declare
  v_user uuid := auth.uid();
  v_match public.matches;
  v_run public.runs;
  v_lobby public.lobbies;
  v_format public.auction_matches;
  v_hol public.higher_or_lower_matches;
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
    if not exists (
      select 1 from public.run_participants where run_id = v_run.id and user_id = v_user
    ) then
      raise exception 'not_match_participant' using errcode = '42501';
    end if;
  else
    select * into v_lobby from public.lobbies where id = v_run.lobby_id for update;
    if v_lobby.host_id <> v_user then raise exception 'not_host' using errcode = '42501'; end if;
  end if;

  if v_match.status <> 'complete'::public.match_status then
    raise exception 'match_not_complete' using errcode = 'P0001';
  end if;
  if exists (select 1 from public.post_game_actions where match_id = p_match_id) then
    raise exception 'post_game_choice_already_made' using errcode = 'P0001';
  end if;

  if p_choice = 'replay'::public.post_game_choice then
    if v_match.game = 'auction_team_builder' then
      select * into v_format from public.auction_matches where match_id = p_match_id;
      if not found or v_format.scoring_mode is null or v_format.roster_preset is null then
        raise exception 'replay_not_supported' using errcode = 'P0001';
      end if;

      v_scoring_mode := coalesce(p_scoring_mode, v_format.scoring_mode);
      v_roster_preset := coalesce(p_roster_preset, v_format.roster_preset);
      v_season_from := coalesce(p_season_from, v_format.season_from);
      v_season_to := coalesce(p_season_to, v_format.season_to);

      if v_scoring_mode not in ('weekly', 'season_total') then
        raise exception 'invalid_scoring_mode' using errcode = 'P0001';
      end if;
      if v_roster_preset not in ('standard', 'full', 'deep') then
        raise exception 'invalid_roster_preset' using errcode = 'P0001';
      end if;
      perform auction_private.resolve_season_range(v_season_from, v_season_to);

      insert into public.runs (lobby_id, mode)
      values (
        case when v_run.lobby_id is null then null else v_lobby.id end,
        case when v_run.lobby_id is null then 'solo'::public.run_mode else 'arcade'::public.run_mode end
      )
      returning * into v_next_run;

      insert into public.run_participants (run_id, user_id, seat)
      select v_next_run.id, user_id, seat from public.run_participants where run_id = v_run.id;

      insert into public.matches (run_id, game, seq, status)
      values (v_next_run.id, v_match.game, 1, 'setup'::public.match_status)
      returning * into v_next_match;

      perform auction_private.deal_board(
        v_next_match.id, null, v_scoring_mode, v_roster_preset, v_season_from, v_season_to
      );
      update public.matches set status = 'playing'::public.match_status, started_at = now()
       where id = v_next_match.id;
      perform auction_private.advance(v_next_match.id);

    elsif v_match.game = 'higher_or_lower' then
      select * into v_hol from public.higher_or_lower_matches where match_id = p_match_id;
      if not found then raise exception 'replay_not_supported' using errcode = 'P0001'; end if;

      v_season_from := coalesce(p_season_from, v_hol.season_from);
      v_season_to := coalesce(p_season_to, v_hol.season_to);

      insert into public.runs (lobby_id, mode)
      values (
        case when v_run.lobby_id is null then null else v_lobby.id end,
        case when v_run.lobby_id is null then 'solo'::public.run_mode else 'arcade'::public.run_mode end
      )
      returning * into v_next_run;

      insert into public.run_participants (run_id, user_id, seat)
      select v_next_run.id, user_id, seat from public.run_participants where run_id = v_run.id;

      insert into public.matches (run_id, game, seq, status)
      values (v_next_run.id, v_match.game, 1, 'setup'::public.match_status)
      returning * into v_next_match;

      perform higher_or_lower_private.deal_board(
        v_next_match.id, null, v_hol.scoring_mode, v_season_from, v_season_to
      );
      update public.matches set status = 'playing'::public.match_status, started_at = now()
       where id = v_next_match.id;
      update public.higher_or_lower_matches
         set phase = 'board_intro', phase_deadline = now() + interval '5 seconds'
       where match_id = v_next_match.id and not is_solo;

    else
      raise exception 'replay_not_supported' using errcode = 'P0001';
    end if;

    insert into public.post_game_actions (match_id, choice, next_match_id)
    values (p_match_id, p_choice, v_next_match.id)
    returning * into v_action;
  else
    insert into public.post_game_actions (match_id, choice)
    values (p_match_id, p_choice)
    returning * into v_action;
  end if;

  return v_action;
end;
$$;
