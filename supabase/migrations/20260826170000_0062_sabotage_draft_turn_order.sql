-- Sabotage draft: turn-based rounds, not simultaneous ones.
--
-- 0051 through 0059 built every round as "everyone picks at once, then one
-- shared guessing window opens for everyone" — the design doc's own decided
-- shape at the time. That shape shipped a real problem in practice: nothing
-- distinguished "whose pick a guess is aimed at" from "who else happens to be
-- picking this round," so every seat's hidden card sat exposed to every other
-- seat's guess for the entire window, all at once. See docs/games/
-- sabotage_draft.md's revised "Round structure" section for the corrected
-- design this migration implements.
--
-- THE NEW SHAPE: a round still has one fixed (or, for round 14, widened)
-- slot, and every seated player still spins their own franchise for it — 0059
-- did not need to change. What changes is that only ONE seat drafts at a
-- time. Seats go in fixed order (seat 1, 2, 3, ...), the same order every
-- round: seat N's turn is pick, then a guess window where every OTHER seat
-- may aim exactly one guess at seat N's hidden card, then the turn passes to
-- seat N+1. Once the last seat's turn in a round closes, the round number
-- advances and seat 1 is back on the clock. `active_seat` is the new pointer
-- that tracks this; `current_round` still means what it always has.
--
-- Round 14 (the X-Factor) is the one place a turn does something extra: per
-- the design doc, its guess window closing opens the active drafter's own
-- private replace-or-discard decision before the turn passes on, rather than
-- everyone deciding at once after the whole round settles. See
-- advance_turn and submit_x_factor_decision below.
--
-- WHAT DOESN'T CHANGE: a pick is still exactly one row per (round, user) in
-- sabotage_draft_picks — turn order only changes *when* that row can be
-- written, not its shape. sabotage_draft_pick_hits' cap of one respin and one
-- exact hit per (round, target) was already keyed by target rather than by
-- "the round's one guessable pick," so it needs nothing here either. Roster
-- assembly, the season simulation, and the tiebreak bracket (0056/0058) read
-- picks and decisions the same way regardless of what order they were made
-- in, so none of that changes.
--
-- WHAT DOES: a guess is no longer aimed at a chosen target — the target is
-- whoever currently holds the turn, so submit_guess drops p_target_user_id
-- entirely. That also means the same guesser can now guess more than once in
-- a single round_number (once per other seat's turn), so
-- sabotage_draft_guesses' primary key gains target_user_id.

-- ------------------------------------------------------------------ turn --

-- Seats are 0-indexed platform-wide (run_participants.seat is dealt as
-- row_number() - 1; see 0009), so the first seat on the clock is 0, not 1.
alter table public.sabotage_draft_matches
  add column active_seat smallint not null default 0 check (active_seat >= 0);

alter type sabotage_draft.round add attribute active_user_id uuid;

-- The one-row lookup every pick/guess/turn-advance path below needs: who
-- currently holds the turn. Centralized for the same reason
-- spin_franchise (0059) is its own function rather than inlined everywhere.
create function sabotage_draft_private.active_user(p_match_id uuid, p_active_seat smallint)
returns uuid
language sql
stable
security definer
set search_path = ''
as $$
  select user_id from public.sabotage_draft_players
   where match_id = p_match_id and seat = p_active_seat;
$$;

create function sabotage_draft_private.player_count(p_match_id uuid)
returns smallint
language sql
stable
security definer
set search_path = ''
as $$
  select count(*)::smallint from public.sabotage_draft_players where match_id = p_match_id;
$$;

create or replace function sabotage_draft_private.round_of(p_match_id uuid)
returns sabotage_draft.round
language sql stable security definer set search_path = '' as $$
  select (m.match_id, m.round_count, m.current_round, r.slot,
          m.pick_deadline, now(), m.guess_deadline, m.x_factor_open,
          sabotage_draft_private.active_user(m.match_id, m.active_seat))::sabotage_draft.round
    from public.sabotage_draft_matches m
    join public.sabotage_draft_rounds r
      on r.match_id = m.match_id and r.round_number = m.current_round
   where m.match_id = p_match_id;
$$;

-- Replaces 0053's advance_round. The old version only ever had "the next
-- round" to move to, because every seat picked and guessed at once; now most
-- turns just hand the clock to the next seat, and only the last seat's turn
-- in a round rolls the round number forward.
drop function if exists sabotage_draft_private.advance_round(uuid);

create function sabotage_draft_private.advance_turn(p_match_id uuid)
returns void
language plpgsql security definer set search_path = '' as $$
declare v_round smallint; v_seat smallint; v_count smallint;
begin
  select current_round, active_seat into v_round, v_seat
    from public.sabotage_draft_matches where match_id = p_match_id;
  v_count := sabotage_draft_private.player_count(p_match_id);

  if v_round = 14 then
    -- The final round's guess window closing doesn't hand the turn straight
    -- to the next seat -- it opens the active drafter's own private
    -- X-Factor decision first. submit_x_factor_decision is what actually
    -- moves to the next seat (or, on the last seat, completes the match)
    -- once that decision is made.
    update public.sabotage_draft_matches
       set guess_deadline = null, x_factor_open = true
     where match_id = p_match_id;
    return;
  end if;

  -- Seats are 0-indexed, so the last seat in the match is v_count - 1.
  if v_seat < v_count - 1 then
    update public.sabotage_draft_matches
       set active_seat = v_seat + 1,
           pick_deadline = now() + interval '45 seconds',
           guess_deadline = null
     where match_id = p_match_id;
  else
    update public.sabotage_draft_matches
       set current_round = v_round + 1,
           active_seat = 0,
           pick_deadline = now() + interval '45 seconds',
           guess_deadline = null
     where match_id = p_match_id;
  end if;
end;
$$;

-- ------------------------------------------------------------------ picks --

-- Only the seat currently on the clock may submit. Once they do, the guess
-- window opens immediately -- there is only ever one pick to wait on now,
-- never a last-of-N to detect, so the old all_picked check is gone too.
create or replace function sabotage_draft.submit_pick(
  p_match_id uuid, p_player_id text, p_season smallint
)
returns public.sabotage_draft_picks
language plpgsql security definer set search_path = '' as $$
declare
  v_user uuid := auth.uid(); v_board public.sabotage_draft_matches;
  v_round public.sabotage_draft_rounds; v_active uuid; v_pick public.sabotage_draft_picks; v_name text;
begin
  if v_user is null then raise exception 'not_authenticated' using errcode = '42501'; end if;
  select sm.* into v_board from public.sabotage_draft_matches sm join public.matches mt on mt.id = sm.match_id
   where sm.match_id = p_match_id and mt.status = 'playing'::public.match_status for update of sm;
  if not found then raise exception 'match_not_playing' using errcode = 'P0001'; end if;
  if not exists (select 1 from public.sabotage_draft_players where match_id = p_match_id and user_id = v_user) then
    raise exception 'not_a_participant' using errcode = '42501'; end if;

  v_active := sabotage_draft_private.active_user(p_match_id, v_board.active_seat);
  if v_user <> v_active then raise exception 'not_your_turn' using errcode = 'P0001'; end if;

  if v_board.pick_deadline is null or v_board.pick_deadline <= now() then raise exception 'pick_window_closed' using errcode = 'P0001'; end if;
  if sabotage_draft_private.has_picked(p_match_id, v_board.current_round, v_user) then raise exception 'already_picked' using errcode = 'P0001'; end if;

  select * into v_round from public.sabotage_draft_rounds where match_id = p_match_id and round_number = v_board.current_round;
  select display_name into v_name from private.av_roster_players
   where franchise_code = sabotage_draft_private.spin_franchise(p_match_id, v_board.current_round, v_user)
     and player_id = p_player_id and season = p_season
     and slot_category = any(sabotage_draft_private.pool_categories(v_round.slot));
  if not found then raise exception 'invalid_pick' using errcode = 'P0001'; end if;

  insert into public.sabotage_draft_picks (match_id, round_number, user_id, player_id, display_name, season, by_timeout)
  values (p_match_id, v_board.current_round, v_user, p_player_id, v_name, p_season, false) returning * into v_pick;
  insert into public.sabotage_draft_pick_statuses (match_id, round_number, user_id) values (p_match_id, v_board.current_round, v_user);
  perform sabotage_draft_private.open_guess_window(p_match_id);
  return v_pick;
end;
$$;

-- Only the active seat can ever be missing a pick now -- the loop over every
-- missing player is gone, since there is exactly one seat who could be one.
create or replace function sabotage_draft_private.expire(p_match_id uuid)
returns boolean
language plpgsql security definer set search_path = '' as $$
declare
  v_board public.sabotage_draft_matches; v_round public.sabotage_draft_rounds;
  v_active uuid; v_drawn record;
begin
  select sm.* into v_board from public.sabotage_draft_matches sm join public.matches mt on mt.id = sm.match_id
   where sm.match_id = p_match_id and mt.status = 'playing'::public.match_status for update of sm;
  if not found then return false; end if;

  v_active := sabotage_draft_private.active_user(p_match_id, v_board.active_seat);

  if v_board.pick_deadline is not null and v_board.pick_deadline <= now() then
    if not sabotage_draft_private.has_picked(p_match_id, v_board.current_round, v_active) then
      select * into v_round from public.sabotage_draft_rounds where match_id = p_match_id and round_number = v_board.current_round;
      select * into v_drawn from sabotage_draft_private.random_pick(
        sabotage_draft_private.spin_franchise(p_match_id, v_board.current_round, v_active),
        sabotage_draft_private.pool_categories(v_round.slot)
      );
      if not found then raise exception 'pool_exhausted' using errcode = 'P0001'; end if;
      insert into public.sabotage_draft_picks (match_id, round_number, user_id, player_id, display_name, season, by_timeout)
      values (p_match_id, v_board.current_round, v_active, v_drawn.player_id, v_drawn.display_name, v_drawn.season, true);
      insert into public.sabotage_draft_pick_statuses (match_id, round_number, user_id) values (p_match_id, v_board.current_round, v_active);
    end if;
    perform sabotage_draft_private.open_guess_window(p_match_id);
    return true;
  end if;

  if v_board.guess_deadline is not null and v_board.guess_deadline <= now() then
    perform sabotage_draft_private.advance_turn(p_match_id);
    return true;
  end if;

  return false;
end;
$$;

-- ---------------------------------------------------------------- guesses --

-- The guess is aimed at whoever holds the turn, never a chosen target, so
-- p_target_user_id is gone. A guesser can now land more than one guess in
-- the same round_number (once per other seat's turn this round), which is
-- exactly what the primary key change below makes room for.
drop function if exists sabotage_draft.submit_guess(uuid, uuid, text, smallint, text, smallint);

alter table public.sabotage_draft_guesses drop constraint sabotage_draft_guesses_pkey;
alter table public.sabotage_draft_guesses add primary key (match_id, round_number, target_user_id, user_id);

create function sabotage_draft.submit_guess(
  p_match_id uuid, p_player_id text, p_season smallint default null,
  p_replacement_player_id text default null, p_replacement_season smallint default null
)
returns public.sabotage_draft_guesses
language plpgsql security definer set search_path = '' as $$
declare
  v_user uuid := auth.uid(); v_board public.sabotage_draft_matches; v_round public.sabotage_draft_rounds;
  v_active uuid; v_franchise text; v_pick public.sabotage_draft_picks; v_drawn record;
  v_guess public.sabotage_draft_guesses; v_replacement_name text;
  v_exact boolean; v_kind text; v_result sabotage_draft.guess_result;
begin
  if v_user is null then raise exception 'not_authenticated' using errcode = '42501'; end if;
  if (p_season is null) <> (p_replacement_player_id is null) or (p_season is null) <> (p_replacement_season is null) then
    raise exception 'invalid_guess_shape' using errcode = 'P0001'; end if;
  select sm.* into v_board from public.sabotage_draft_matches sm join public.matches mt on mt.id = sm.match_id
   where sm.match_id = p_match_id and mt.status = 'playing'::public.match_status for update of sm;
  if not found then raise exception 'match_not_playing' using errcode = 'P0001'; end if;
  if not exists (select 1 from public.sabotage_draft_players where match_id = p_match_id and user_id = v_user) then
    raise exception 'not_a_participant' using errcode = '42501'; end if;

  v_active := sabotage_draft_private.active_user(p_match_id, v_board.active_seat);
  -- The seat on the clock has no one to guess at but themselves -- the
  -- window is other-directed by construction now, not a chosen target, so
  -- there is nothing left for the active drafter to submit here.
  if v_user = v_active then raise exception 'not_your_turn' using errcode = 'P0001'; end if;

  if v_board.guess_deadline is null or v_board.guess_deadline <= now() then raise exception 'guess_window_closed' using errcode = 'P0001'; end if;
  if exists (
    select 1 from public.sabotage_draft_guesses
     where match_id = p_match_id and round_number = v_board.current_round
       and target_user_id = v_active and user_id = v_user
  ) then raise exception 'already_guessed' using errcode = 'P0001'; end if;

  select * into v_round from public.sabotage_draft_rounds where match_id = p_match_id and round_number = v_board.current_round;
  v_franchise := sabotage_draft_private.spin_franchise(p_match_id, v_board.current_round, v_active);
  if not exists (
    select 1 from private.av_roster_players
     where franchise_code = v_franchise and player_id = p_player_id
       and slot_category = any(sabotage_draft_private.pool_categories(v_round.slot))
  ) then raise exception 'invalid_guess' using errcode = 'P0001'; end if;

  if p_season is not null then
    select display_name into v_replacement_name from private.av_roster_players
     where franchise_code = v_franchise and player_id = p_replacement_player_id and season = p_replacement_season
       and slot_category = any(sabotage_draft_private.pool_categories(v_round.slot));
    if not found then raise exception 'invalid_replacement' using errcode = 'P0001'; end if;
  end if;

  select * into v_pick from public.sabotage_draft_picks
   where match_id = p_match_id and round_number = v_board.current_round and user_id = v_active;
  v_exact := v_pick.player_id = p_player_id and (p_season is null or v_pick.season = p_season);
  v_kind := case when p_season is null then 'respin' else 'sabotage' end;

  if v_exact and not exists (
    select 1 from public.sabotage_draft_pick_hits
     where match_id = p_match_id and round_number = v_board.current_round
       and target_user_id = v_active and kind = v_kind
  ) then
    insert into public.sabotage_draft_pick_hits (match_id, round_number, target_user_id, kind, guesser_user_id)
    values (p_match_id, v_board.current_round, v_active, v_kind, v_user);
    if v_kind = 'respin' then
      select * into v_drawn from sabotage_draft_private.random_pick(v_franchise, sabotage_draft_private.pool_categories(v_round.slot));
      update public.sabotage_draft_picks set player_id = v_drawn.player_id, display_name = v_drawn.display_name, season = v_drawn.season, by_timeout = false
       where match_id = p_match_id and round_number = v_board.current_round and user_id = v_active;
      v_result := 'respun';
    else
      update public.sabotage_draft_picks set player_id = p_replacement_player_id, display_name = v_replacement_name, season = p_replacement_season, by_timeout = false
       where match_id = p_match_id and round_number = v_board.current_round and user_id = v_active;
      v_result := 'sabotaged';
    end if;
  else
    v_result := 'miss';
  end if;

  insert into public.sabotage_draft_guesses (match_id, round_number, user_id, target_user_id, player_id, season, replacement_player_id, replacement_season, result)
  values (p_match_id, v_board.current_round, v_user, v_active, p_player_id, p_season, p_replacement_player_id, p_replacement_season, v_result)
  returning * into v_guess;
  return v_guess;
end;
$$;

-- -------------------------------------------------------------- x-factor --

-- Unchanged from 0056 up through the decision insert. What's new: the
-- decision is what hands the turn to the next seat's round-14 pick window
-- (or, on the last seat, completes the match) -- there is no longer a
-- separate all-players-at-once decision phase for maybe_complete to wait on
-- independently of turn order.
create or replace function sabotage_draft.submit_x_factor_decision(
  p_match_id uuid, p_replace_slot text default null
)
returns public.sabotage_draft_x_factor_decisions
language plpgsql security definer set search_path = '' as $$
declare
  v_user uuid := auth.uid(); v_board public.sabotage_draft_matches;
  v_active uuid; v_count smallint; v_decision public.sabotage_draft_x_factor_decisions;
begin
  if v_user is null then raise exception 'not_authenticated' using errcode = '42501'; end if;
  select sm.* into v_board from public.sabotage_draft_matches sm join public.matches mt on mt.id = sm.match_id
   where sm.match_id = p_match_id and mt.status = 'playing'::public.match_status for update of sm;
  if not found then raise exception 'match_not_playing' using errcode = 'P0001'; end if;
  if not exists (select 1 from public.sabotage_draft_players where match_id = p_match_id and user_id = v_user) then
    raise exception 'not_a_participant' using errcode = '42501'; end if;

  v_active := sabotage_draft_private.active_user(p_match_id, v_board.active_seat);
  if v_user <> v_active then raise exception 'not_your_turn' using errcode = 'P0001'; end if;

  if v_board.current_round <> 14
     or not v_board.x_factor_open
     or v_board.pick_deadline is not null
     or v_board.guess_deadline is not null then
    raise exception 'x_factor_not_ready' using errcode = 'P0001';
  end if;

  if exists (
    select 1 from public.sabotage_draft_x_factor_decisions
     where match_id = p_match_id and user_id = v_user
  ) then
    raise exception 'x_factor_already_decided' using errcode = 'P0001';
  end if;

  if p_replace_slot is not null then
    if p_replace_slot not in ('QB', 'RB1', 'RB2', 'WR1', 'WR2', 'WR3', 'TE') then
      raise exception 'invalid_x_factor_slot' using errcode = 'P0001';
    end if;

    if not exists (
      select 1
        from public.sabotage_draft_picks p
        join public.sabotage_draft_rounds r
          on r.match_id = p.match_id and r.round_number = p.round_number
       where p.match_id = p_match_id
         and p.user_id = v_user
         and r.slot = p_replace_slot
         and p.round_number between 1 and 13
    ) then
      raise exception 'x_factor_slot_unavailable' using errcode = 'P0001';
    end if;
  end if;

  insert into public.sabotage_draft_x_factor_decisions (match_id, user_id, replace_slot)
  values (p_match_id, v_user, p_replace_slot)
  returning * into v_decision;

  v_count := sabotage_draft_private.player_count(p_match_id);
  if v_board.active_seat < v_count - 1 then
    update public.sabotage_draft_matches
       set active_seat = v_board.active_seat + 1,
           x_factor_open = false,
           pick_deadline = now() + interval '45 seconds'
     where match_id = p_match_id;
  else
    -- The last seat's own decision is also, unavoidably, the last decision
    -- the match needs full stop -- maybe_complete's unanimity check and this
    -- being the final turn agree by construction, not by coincidence.
    perform sabotage_draft_private.maybe_complete(p_match_id);
  end if;

  return v_decision;
end;
$$;

-- ---------------------------------------------------------------- privileges --

revoke all on function sabotage_draft_private.active_user(uuid, smallint) from public, anon, authenticated;
revoke all on function sabotage_draft_private.player_count(uuid)           from public, anon, authenticated;
revoke all on function sabotage_draft_private.advance_turn(uuid)           from public, anon, authenticated;

revoke all on function sabotage_draft.submit_guess(uuid, text, smallint, text, smallint) from public, anon;
grant execute on function sabotage_draft.submit_guess(uuid, text, smallint, text, smallint) to authenticated;
