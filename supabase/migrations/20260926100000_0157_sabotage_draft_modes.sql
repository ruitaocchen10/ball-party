-- Sabotage draft game modes: Full (the existing 14 rounds), Standard (10) and
-- Quick (7), chosen when the host starts the match.
--
--   full      QB RB1 RB2 WR1 WR2 WR3 TE OL DL LB CB S ST X_FACTOR   (14)
--   standard  QB RB1 RB2 WR1 WR2 TE FLEX DEF ST X_FACTOR            (10)
--   quick     QB RB1 WR1 TE FLEX DEF X_FACTOR                       (7)
--
-- FLEX is any RB/WR/TE. DEF is any DL/LB/CB/S, one player on the same AV
-- scale as everything else (there is no team-defense data to draft as a unit).
-- X_FACTOR stays the last round of every mode and may upgrade any offensive
-- skill slot in the mode, FLEX included.
--
-- Everything that hardcoded 14 or 13 now reads the match's own round_count, and
-- the season is graded against a per-mode baseline. Each baseline is built the
-- way 0076's 93 was: for every real NFL team-season 2006-2025 in
-- private.av_roster_players, sum that team's best player at each of the mode's
-- slots (FLEX = the best skill player left over after the fixed RB/WR/TE
-- slots, DEF = its best DL/LB/CB/S), then average over the 608 team-seasons.
-- That gives 62 for standard (9 cards) and 52 for quick (6 cards).
--
-- The logistic's 25-point divisor is for a 13-card, 93-strength roster; with
-- fewer cards the same relative edge is a smaller absolute gap, so the divisor
-- scales with the baseline (25 * baseline / 93). A roster 20% over its mode's
-- baseline therefore wins about the same share of games in any mode.
--
-- Existing matches keep mode 'full' and behave exactly as before.

alter table public.sabotage_draft_matches
  add column mode text not null default 'full'
  constraint sabotage_draft_matches_mode_check check (mode in ('full', 'standard', 'quick'));

alter table public.sabotage_draft_matches drop constraint sabotage_draft_matches_round_count_check;
alter table public.sabotage_draft_matches
  add constraint sabotage_draft_matches_round_count_check check (round_count in (7, 10, 14));

alter table public.sabotage_draft_rounds drop constraint sabotage_draft_rounds_slot_check;
alter table public.sabotage_draft_rounds add constraint sabotage_draft_rounds_slot_check check (slot in (
  'QB', 'RB1', 'RB2', 'WR1', 'WR2', 'WR3', 'TE', 'FLEX',
  'OL', 'DL', 'LB', 'CB', 'S', 'DEF', 'ST', 'X_FACTOR'
));

alter table public.sabotage_draft_x_factor_decisions drop constraint sabotage_draft_x_factor_decisions_replace_slot_check;
alter table public.sabotage_draft_x_factor_decisions add constraint sabotage_draft_x_factor_decisions_replace_slot_check
  check (replace_slot is null or replace_slot in ('QB', 'RB1', 'RB2', 'WR1', 'WR2', 'WR3', 'TE', 'FLEX'));

create function sabotage_draft_private.mode_slots(p_mode text)
returns text[]
language plpgsql
immutable
set search_path = ''
as $$
begin
  return case p_mode
    when 'full'     then array['QB', 'RB1', 'RB2', 'WR1', 'WR2', 'WR3', 'TE', 'OL', 'DL', 'LB', 'CB', 'S', 'ST', 'X_FACTOR']
    when 'standard' then array['QB', 'RB1', 'RB2', 'WR1', 'WR2', 'TE', 'FLEX', 'DEF', 'ST', 'X_FACTOR']
    when 'quick'    then array['QB', 'RB1', 'WR1', 'TE', 'FLEX', 'DEF', 'X_FACTOR']
    else null
  end;
end;
$$;

-- Per-mode fixed baseline; see the header for how the numbers were derived.
create function sabotage_draft_private.baseline_roster_strength(p_mode text)
returns integer
language sql
immutable
set search_path = ''
as $$
  select case p_mode when 'standard' then 62 when 'quick' then 52 else 93 end;
$$;

-- 25 for a full roster, proportionally tighter for the smaller ones.
create function sabotage_draft_private.strength_scale(p_mode text)
returns double precision
language sql
immutable
set search_path = ''
as $$
  select 25.0 * sabotage_draft_private.baseline_roster_strength(p_mode) / 93.0;
$$;

create function sabotage_draft_private.win_probability(p_strength_a integer, p_strength_b integer, p_scale double precision)
returns double precision
language sql
immutable
set search_path = ''
as $$
  select 1.0 / (1.0 + exp(-((p_strength_a - p_strength_b)::double precision / p_scale)));
$$;

revoke all on function sabotage_draft_private.mode_slots(text) from public, anon, authenticated;
revoke all on function sabotage_draft_private.baseline_roster_strength(text) from public, anon, authenticated;
revoke all on function sabotage_draft_private.strength_scale(text) from public, anon, authenticated;
revoke all on function sabotage_draft_private.win_probability(integer, integer, double precision) from public, anon, authenticated;

CREATE OR REPLACE FUNCTION sabotage_draft_private.pool_categories(p_slot text)
 RETURNS text[]
 LANGUAGE plpgsql
 IMMUTABLE
 SET search_path TO ''
AS $function$
declare v_categories text[];
begin
  v_categories := case p_slot
    when 'QB'       then array['QB']
    when 'RB1'      then array['RB']
    when 'RB2'      then array['RB']
    when 'WR1'      then array['WR']
    when 'WR2'      then array['WR']
    when 'WR3'      then array['WR']
    when 'TE'       then array['TE']
    when 'OL'       then array['OL']
    when 'DL'       then array['DL']
    when 'LB'       then array['LB']
    when 'CB'       then array['CB']
    when 'S'        then array['S']
    when 'FLEX'     then array['RB', 'WR', 'TE']
    when 'DEF'      then array['DL', 'LB', 'CB', 'S']
    when 'ST'       then array['ST']
    when 'X_FACTOR' then array['QB', 'RB', 'WR', 'TE']
  end;

  -- The slot column is CHECK-constrained to exactly these values, so an
  -- unmapped slot here means this function drifted from that constraint, not
  -- that a caller passed something unexpected.
  if v_categories is null then
    raise exception 'unknown_slot' using errcode = 'P0001';
  end if;

  return v_categories;
end;
$function$
;
CREATE OR REPLACE FUNCTION sabotage_draft_private.advance_turn(p_match_id uuid)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare v_round smallint; v_seat smallint; v_count smallint; v_rounds smallint;
begin
  select current_round, active_seat, round_count into v_round, v_seat, v_rounds
    from public.sabotage_draft_matches where match_id = p_match_id;
  v_count := sabotage_draft_private.player_count(p_match_id);

  if v_round = v_rounds then
    update public.sabotage_draft_matches set turn_deadline = null, x_factor_open = true
     where match_id = p_match_id;
    return;
  end if;

  if v_seat < v_count - 1 then
    update public.sabotage_draft_matches
       set active_seat = v_seat + 1, turn_deadline = now() + interval '30 seconds'
     where match_id = p_match_id;
  else
    update public.sabotage_draft_matches
       set current_round = v_round + 1, active_seat = 0, turn_deadline = now() + interval '30 seconds'
     where match_id = p_match_id;
  end if;
end;
$function$
;
CREATE OR REPLACE FUNCTION sabotage_draft.submit_x_factor_decision(p_match_id uuid, p_replace_slot text DEFAULT NULL::text)
 RETURNS sabotage_draft_x_factor_decisions
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_user uuid := auth.uid(); v_board public.sabotage_draft_matches;
  v_active uuid; v_count smallint; v_decision public.sabotage_draft_x_factor_decisions;
  v_category text;
begin
  if v_user is null then raise exception 'not_authenticated' using errcode = '42501'; end if;
  select sm.* into v_board from public.sabotage_draft_matches sm join public.matches mt on mt.id = sm.match_id
   where sm.match_id = p_match_id and mt.status = 'playing'::public.match_status for update of sm;
  if not found then raise exception 'match_not_playing' using errcode = 'P0001'; end if;
  if not exists (select 1 from public.sabotage_draft_players where match_id = p_match_id and user_id = v_user) then
    raise exception 'not_a_participant' using errcode = '42501';
  end if;

  v_active := sabotage_draft_private.active_user(p_match_id, v_board.active_seat);
  if v_user <> v_active then raise exception 'not_your_turn' using errcode = 'P0001'; end if;
  if v_board.current_round <> v_board.round_count or not v_board.x_factor_open or v_board.turn_deadline is not null then
    raise exception 'x_factor_not_ready' using errcode = 'P0001';
  end if;
  if exists (select 1 from public.sabotage_draft_x_factor_decisions where match_id = p_match_id and user_id = v_user) then
    raise exception 'x_factor_already_decided' using errcode = 'P0001';
  end if;

  if p_replace_slot is not null then
    if p_replace_slot not in ('QB', 'RB1', 'RB2', 'WR1', 'WR2', 'WR3', 'TE', 'FLEX')
       or p_replace_slot <> all(sabotage_draft_private.mode_slots(v_board.mode)) then
      raise exception 'invalid_x_factor_slot' using errcode = 'P0001';
    end if;
    select pool.slot_category into v_category
      from public.sabotage_draft_picks pick
      join public.sabotage_draft_round_spins spin on spin.match_id = pick.match_id and spin.round_number = pick.round_number and spin.user_id = pick.user_id
      join private.av_roster_players pool on pool.franchise_code = spin.franchise_code and pool.player_id = pick.player_id and pool.season = pick.season
     where pick.match_id = p_match_id and pick.user_id = v_user and pick.round_number = v_board.round_count;
    if not found then raise exception 'x_factor_pick_unavailable' using errcode = 'P0001'; end if;
    if not ((v_category = 'QB' and p_replace_slot = 'QB') or (v_category = 'RB' and p_replace_slot in ('RB1', 'RB2')) or (v_category = 'WR' and p_replace_slot in ('WR1', 'WR2', 'WR3')) or (v_category = 'TE' and p_replace_slot = 'TE') or (v_category in ('RB', 'WR', 'TE') and p_replace_slot = 'FLEX')) then
      raise exception 'x_factor_position_mismatch' using errcode = 'P0001';
    end if;
  end if;

  insert into public.sabotage_draft_x_factor_decisions (match_id, user_id, replace_slot)
  values (p_match_id, v_user, p_replace_slot) returning * into v_decision;

  v_count := sabotage_draft_private.player_count(p_match_id);
  if v_board.active_seat < v_count - 1 then
    update public.sabotage_draft_matches
       set active_seat = v_board.active_seat + 1, x_factor_open = false,
           turn_deadline = now() + interval '30 seconds'
     where match_id = p_match_id;
  else
    perform sabotage_draft_private.maybe_complete(p_match_id);
  end if;
  return v_decision;
end;
$function$
;
CREATE OR REPLACE FUNCTION sabotage_draft_private.roster_strengths(p_match_id uuid)
 RETURNS TABLE(user_id uuid, roster_strength integer)
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
  with final_cards as (
    select p.user_id,
           case when d.replace_slot = r.slot then x.player_id else p.player_id end as player_id,
           case when d.replace_slot = r.slot then x.season else p.season end as season,
           case when d.replace_slot = r.slot then 'X_FACTOR' else r.slot end as source_slot,
           case when d.replace_slot = r.slot then m.round_count else p.round_number end as source_round
      from public.sabotage_draft_picks p
      join public.sabotage_draft_rounds r on r.match_id = p.match_id and r.round_number = p.round_number
      join public.sabotage_draft_x_factor_decisions d on d.match_id = p.match_id and d.user_id = p.user_id
      join public.sabotage_draft_matches m on m.match_id = p.match_id
      join public.sabotage_draft_picks x on x.match_id = p.match_id and x.user_id = p.user_id and x.round_number = m.round_count
     where p.match_id = p_match_id and p.round_number < m.round_count
  )
  select c.user_id, sum(pool.av)::integer
    from final_cards c
    join public.sabotage_draft_round_spins spin
      on spin.match_id = p_match_id
     and spin.user_id = c.user_id
     and spin.round_number = c.source_round
    join private.av_roster_players pool
      on pool.franchise_code = spin.franchise_code
     and pool.player_id = c.player_id and pool.season = c.season
     and pool.slot_category = any(sabotage_draft_private.pool_categories(c.source_slot))
   group by c.user_id;
$function$
;
CREATE OR REPLACE FUNCTION sabotage_draft_private.simulate_season(p_match_id uuid, p_seed double precision DEFAULT NULL::double precision)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_seed double precision; v_baseline integer; v_scale double precision; v_mode text; v_player record; v_game int; v_wins smallint;
  v_tie record;
begin
  select coalesce(p_seed, b.seed) into v_seed from sabotage_draft_private.boards b where b.match_id = p_match_id;
  if v_seed is null then raise exception 'board_not_found' using errcode = 'P0001'; end if;
  perform setseed(v_seed); set local max_parallel_workers_per_gather = 0;
  if not exists (select 1 from sabotage_draft_private.roster_strengths(p_match_id)) then
    raise exception 'incomplete_roster' using errcode = 'P0001';
  end if;
  select sm.mode into v_mode from public.sabotage_draft_matches sm where sm.match_id = p_match_id;
  v_baseline := sabotage_draft_private.baseline_roster_strength(v_mode);
  v_scale := sabotage_draft_private.strength_scale(v_mode);
  for v_player in select * from sabotage_draft_private.roster_strengths(p_match_id) order by user_id loop
    v_wins := 0;
    for v_game in 1 .. 17 loop
      if random() < sabotage_draft_private.win_probability(v_player.roster_strength, v_baseline, v_scale) then v_wins := v_wins + 1; end if;
    end loop;
    insert into public.sabotage_draft_standings (match_id, user_id, roster_strength, wins, losses, tiebreak_rank)
    values (p_match_id, v_player.user_id, v_player.roster_strength, v_wins, 17 - v_wins, 1);
  end loop;
  insert into sabotage_draft_private.seasons (match_id, seed) values (p_match_id, v_seed);
  -- Table-wide starting rank for every player's win tier: 1 plus however many
  -- other players strictly out-won them. Correct as-is for anyone whose win
  -- count is unique; break_record_tie below only needs to spread the players
  -- who share a tier across that tier's own rank range.
  update public.sabotage_draft_standings s set tiebreak_rank = 1 + (
    select count(*) from public.sabotage_draft_standings o
     where o.match_id = p_match_id and o.wins > s.wins
  ) where s.match_id = p_match_id;
  for v_tie in select wins, array_agg(user_id order by user_id) as players, min(tiebreak_rank) as base_rank
                  from public.sabotage_draft_standings where match_id = p_match_id
                 group by wins having count(*) > 1 loop
    perform sabotage_draft_private.break_record_tie(p_match_id, v_tie.wins, v_tie.players, v_tie.base_rank);
  end loop;
  perform private.finish_match(p_match_id, (
    select jsonb_object_agg(user_id::text, (wins * 1000 + (100 - tiebreak_rank))::numeric)
      from public.sabotage_draft_standings where match_id = p_match_id
  ));
end;
$function$
;
CREATE OR REPLACE FUNCTION sabotage_draft_private.break_record_tie(p_match_id uuid, p_wins smallint, p_players uuid[], p_base_rank smallint)
 RETURNS TABLE(user_id uuid, tiebreak_rank smallint)
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_remaining uuid[] := p_players; v_next uuid[]; v_a uuid; v_b uuid;
  v_round smallint := 1; v_game smallint; v_i int;
  v_rank smallint := p_base_rank + array_length(p_players, 1) - 1;
  v_strength_a integer; v_strength_b integer; v_winner uuid;
  v_score_a smallint; v_score_b smallint; v_loser_score smallint; v_margin smallint;
  v_scale double precision;
begin
  v_scale := sabotage_draft_private.strength_scale(
    (select sm.mode from public.sabotage_draft_matches sm where sm.match_id = p_match_id));
  while array_length(v_remaining, 1) > 1 loop
    select array_agg(u.user_id order by random()) into v_remaining
      from unnest(v_remaining) as u(user_id);
    v_next := array[]::uuid[]; v_game := 0;
    for v_i in 1 .. array_length(v_remaining, 1) by 2 loop
      v_game := v_game + 1; v_a := v_remaining[v_i]; v_b := v_remaining[v_i + 1];
      v_score_a := null; v_score_b := null;
      if v_b is null then
        v_winner := v_a;
      else
        select s.roster_strength into v_strength_a from public.sabotage_draft_standings s where s.match_id = p_match_id and s.user_id = v_a;
        select s.roster_strength into v_strength_b from public.sabotage_draft_standings s where s.match_id = p_match_id and s.user_id = v_b;
        v_winner := case when random() < sabotage_draft_private.win_probability(v_strength_a, v_strength_b, v_scale) then v_a else v_b end;
        v_loser_score := (10 + floor(random() * 15))::smallint;
        v_margin := (1 + floor(random() * 14))::smallint;
        if v_winner = v_a then
          v_score_a := v_loser_score + v_margin; v_score_b := v_loser_score;
        else
          v_score_a := v_loser_score; v_score_b := v_loser_score + v_margin;
        end if;
      end if;
      insert into public.sabotage_draft_tiebreak_games
        (match_id, record_wins, bracket_round, game_number, player_a, player_b, winner_user_id, player_a_score, player_b_score)
      values (p_match_id, p_wins, v_round, v_game, v_a, v_b, v_winner, v_score_a, v_score_b);
      v_next := array_append(v_next, v_winner);
    end loop;
    update public.sabotage_draft_standings s set tiebreak_rank = v_rank
     where s.match_id = p_match_id and s.user_id = any(v_remaining) and s.user_id <> all(v_next);
    v_remaining := v_next; v_rank := v_rank - array_length(v_next, 1); v_round := v_round + 1;
  end loop;
  update public.sabotage_draft_standings s set tiebreak_rank = p_base_rank
   where s.match_id = p_match_id and s.user_id = v_remaining[1];
  return query select s.user_id, s.tiebreak_rank from public.sabotage_draft_standings s
   where s.match_id = p_match_id and s.user_id = any(p_players);
end;
$function$
;
drop function sabotage_draft_private.deal_board(uuid, double precision);

CREATE OR REPLACE FUNCTION sabotage_draft_private.deal_board(p_match_id uuid, p_seed double precision DEFAULT NULL::double precision, p_mode text DEFAULT 'full'::text)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_seed  double precision := coalesce(p_seed, random());
  v_n     int;
  v_i     smallint;
  v_slot  text;
  v_franchise text;
  v_player record;
  v_slots text[] := sabotage_draft_private.mode_slots(p_mode);
begin
  if v_slots is null then raise exception 'invalid_mode' using errcode = '22023'; end if;
  perform setseed(v_seed);
  set local max_parallel_workers_per_gather = 0;

  insert into public.sabotage_draft_players (match_id, user_id, seat)
  select p_match_id, rp.user_id, rp.seat
    from public.run_participants rp
    join public.matches m on m.run_id = rp.run_id
   where m.id = p_match_id;

  select count(*) into v_n from public.sabotage_draft_players where match_id = p_match_id;
  if v_n < 2 then raise exception 'too_few_players' using errcode = 'P0001'; end if;

  for v_i in 1 .. array_length(v_slots, 1) loop
    v_slot := v_slots[v_i];
    insert into public.sabotage_draft_rounds (match_id, round_number, slot)
    values (p_match_id, v_i, v_slot);

    for v_player in
      select sp.user_id from public.sabotage_draft_players sp
       where sp.match_id = p_match_id order by sp.seat
    loop
      select r.franchise_code into v_franchise
        from private.av_roster_players r
       where r.slot_category = any(sabotage_draft_private.pool_categories(v_slot))
       group by r.franchise_code order by random() limit 1;
      if not found then raise exception 'pool_exhausted' using errcode = 'P0001'; end if;
      insert into public.sabotage_draft_round_spins (match_id, round_number, user_id, franchise_code)
      values (p_match_id, v_i, v_player.user_id, v_franchise);
    end loop;
  end loop;

  insert into public.sabotage_draft_matches (match_id, mode, round_count, current_round, active_seat, turn_deadline)
  values (p_match_id, p_mode, array_length(v_slots, 1), 1, 0, now() + interval '30 seconds');
  insert into sabotage_draft_private.boards (match_id, seed) values (p_match_id, v_seed);
end;
$function$
;
revoke all on function sabotage_draft_private.deal_board(uuid, double precision, text) from public, anon, authenticated;

drop function sabotage_draft.start(uuid);

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

  return sabotage_draft_private.round_of(p_match_id);
end;
$function$
;
revoke all on function sabotage_draft.start(uuid, text) from public, anon;
grant execute on function sabotage_draft.start(uuid, text) to authenticated;

-- Grading a FLEX or DEF pick needs the position the player actually plays,
-- not the slot's label, so pick_avs now says which pool category each pick
-- came from. Same visibility rules as before; only a column is added.
drop function sabotage_draft.pick_avs(uuid);

CREATE OR REPLACE FUNCTION sabotage_draft.pick_avs(p_match_id uuid)
 RETURNS TABLE(user_id uuid, round_number smallint, av smallint, slot_category text)
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
begin
  if not private.is_match_member(p_match_id) then
    raise exception 'not_a_participant' using errcode = '42501';
  end if;

  return query
    select p.user_id, p.round_number, pool.av, pool.slot_category
      from public.sabotage_draft_picks p
      join public.sabotage_draft_rounds r
        on r.match_id = p.match_id and r.round_number = p.round_number
      join public.sabotage_draft_round_spins spin
        on spin.match_id = p.match_id and spin.round_number = p.round_number and spin.user_id = p.user_id
      join private.av_roster_players pool
        on pool.franchise_code = spin.franchise_code
       and pool.player_id = p.player_id and pool.season = p.season
       and pool.slot_category = any(sabotage_draft_private.pool_categories(r.slot))
     where p.match_id = p_match_id
       and (
         p.user_id = auth.uid()
         or exists (
           select 1
             from public.sabotage_draft_matches m
             join public.sabotage_draft_players sp
               on sp.match_id = m.match_id and sp.user_id = p.user_id
            where m.match_id = p.match_id
              and (
                p.round_number < m.current_round
                or (p.round_number = m.current_round and sp.seat < m.active_seat)
              )
         )
       );
end;
$function$
;
revoke all on function sabotage_draft.pick_avs(uuid) from public, anon, authenticated;
grant execute on function sabotage_draft.pick_avs(uuid) to authenticated;
