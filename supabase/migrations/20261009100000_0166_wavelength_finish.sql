-- Wavelength match resolution: co-op results, versus tiebreaks, and sudden
-- death.  The helpers below are private so that every terminal path (a click
-- or a clock expiry) reaches the platform through the same transaction.

create function wavelength_private.deal_sudden_death(p_match_id uuid)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_cfg jsonb := wavelength_private.config();
  v_round smallint;
  v_team smallint;
  v_psychics uuid[];
  v_psychic uuid;
  v_guesser uuid;
  v_card record;
  v_scale integer := (v_cfg ->> 'scale_max')::integer;
  v_margin integer := (v_cfg ->> 'wedge_width')::integer * 5 / 2;
begin
  select coalesce(max(round), 0)::smallint + 1 into v_round
    from public.wavelength_rounds where match_id = p_match_id;

  -- One clue per team.  Rotate each team's psychic so repeated sudden-death
  -- pairs continue the same fair turn order as the regular board.
  for v_team in 0..1 loop
    select array_agg(user_id order by seat) into v_psychics
      from public.wavelength_players
     where match_id = p_match_id and team = v_team;
    select v_psychics[(count(*)::integer % cardinality(v_psychics)) + 1]
      into v_psychic
      from public.wavelength_rounds r
      join public.wavelength_players p
        on p.match_id = r.match_id and p.user_id = r.psychic_id
     where r.match_id = p_match_id and p.team = v_team;
    select user_id into v_guesser from public.wavelength_players
     where match_id = p_match_id and team = v_team and user_id <> v_psychic;

    insert into public.wavelength_rounds (match_id, round, psychic_id, guesser_id)
    values (p_match_id, v_round + v_team, v_psychic, v_guesser);
    select d.card_id, d.left_label, d.right_label into v_card
      from wavelength_private.deck d
     where not exists (
       select 1 from public.wavelength_cards c
        where c.match_id = p_match_id and c.card_id = d.card_id
     )
     order by random() limit 1;
    if not found then raise exception 'deck_exhausted' using errcode = 'P0001'; end if;
    insert into public.wavelength_cards (match_id, round, card_id, left_label, right_label)
    values (p_match_id, v_round + v_team, v_card.card_id, v_card.left_label, v_card.right_label);
    insert into public.wavelength_targets (match_id, round, target)
    values (p_match_id, v_round + v_team,
            v_margin + floor(random() * (v_scale - 2 * v_margin + 1))::integer);
  end loop;

  update public.wavelength_matches
     set current_round = v_round,
         phase = 'fill',
         phase_deadline = now() + make_interval(secs => (v_cfg ->> 'fill_seconds_per_clue')::integer),
         phase_started_at = now()
   where match_id = p_match_id;
end;
$$;

create function wavelength_private.finish_if_ready(p_match_id uuid)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_board public.wavelength_matches;
  v_score0 smallint;
  v_score1 smallint;
  v_bullseyes0 smallint;
  v_bullseyes1 smallint;
  v_winner smallint;
  v_score smallint;
  v_bullseyes smallint;
  v_stars smallint;
  v_scores jsonb;
  v_target integer;
begin
  select * into v_board from public.wavelength_matches where match_id = p_match_id;
  if exists (select 1 from public.wavelength_rounds where match_id = p_match_id and status in ('pending', 'open')) then
    return;
  end if;

  select coalesce(sum(points) filter (where p.team = 0), 0)::smallint,
         coalesce(sum(points) filter (where p.team = 1), 0)::smallint,
         coalesce(count(*) filter (where p.team = 0 and r.points = 4), 0)::smallint,
         coalesce(count(*) filter (where p.team = 1 and r.points = 4), 0)::smallint
    into v_score0, v_score1, v_bullseyes0, v_bullseyes1
    from public.wavelength_rounds r
    join public.wavelength_players p on p.match_id = r.match_id and p.user_id = r.psychic_id
   where r.match_id = p_match_id;

  if v_board.mode = 'versus' and v_score0 = v_score1 and v_bullseyes0 = v_bullseyes1 then
    perform wavelength_private.deal_sudden_death(p_match_id);
    return;
  end if;

  if v_board.mode = 'coop' then
    v_score := v_score0;
    v_bullseyes := v_bullseyes0;
    v_target := (wavelength_private.config() -> 'presets' -> v_board.preset ->> 'target')::integer;
    v_stars := case
      when v_score >= (wavelength_private.config() -> 'presets' -> v_board.preset ->> 'star3')::integer then 3
      when v_score >= (wavelength_private.config() -> 'presets' -> v_board.preset ->> 'star2')::integer then 2
      when v_score >= v_target then 1 else 0 end;
    insert into public.wavelength_results (match_id, mode, preset, outcome, score, bullseyes, stars)
    values (p_match_id, 'coop', v_board.preset,
            case when v_score >= v_target then 'win' else 'lose' end,
            v_score, v_bullseyes, v_stars);
    select jsonb_object_agg(user_id::text, v_score) into v_scores
      from public.wavelength_players where match_id = p_match_id;
  else
    v_winner := case when v_score0 > v_score1 or (v_score0 = v_score1 and v_bullseyes0 > v_bullseyes1) then 0 else 1 end;
    v_score := case when v_winner = 0 then v_score0 else v_score1 end;
    v_bullseyes := case when v_winner = 0 then v_bullseyes0 else v_bullseyes1 end;
    insert into public.wavelength_results (match_id, mode, preset, outcome, score, bullseyes, stars)
    values (p_match_id, 'versus', null, 'team_' || v_winner || '_win', v_score, v_bullseyes, null);
    select jsonb_object_agg(p.user_id::text, (case when p.team = 0 then v_score0 * 1000 + v_bullseyes0 else v_score1 * 1000 + v_bullseyes1 end)) into v_scores
      from public.wavelength_players p where p.match_id = p_match_id;
  end if;

  update public.wavelength_matches set phase = 'complete', phase_deadline = null, phase_started_at = now()
   where match_id = p_match_id;
  perform private.finish_match(p_match_id, v_scores);
  update public.match_players mp set team = wp.team
    from public.wavelength_players wp
   where mp.match_id = p_match_id and wp.match_id = mp.match_id and wp.user_id = mp.user_id;
end;
$$;

-- Both click and expiry settle through this function.  Replacing it keeps the
-- clock slice immutable while giving its final reveal a real result.
create or replace function wavelength_private.settle_guess(p_match_id uuid, p_round smallint, p_position integer)
returns void language plpgsql security definer set search_path = '' as $$
declare v_board public.wavelength_matches; v_target smallint; v_width integer := (wavelength_private.config() ->> 'wedge_width')::integer; v_points smallint; v_next smallint;
begin
  select * into v_board from public.wavelength_matches where match_id = p_match_id;
  select target into v_target from public.wavelength_targets where match_id = p_match_id and round = p_round;
  v_points := case when abs(p_position - v_target) <= v_width / 2 then 4 when abs(p_position - v_target) <= v_width * 3 / 2 then 3 when abs(p_position - v_target) <= v_width * 5 / 2 then 2 else 0 end;
  update public.wavelength_rounds set status = 'locked', points = v_points, revealed_target = v_target where match_id = p_match_id and round = p_round;
  perform wavelength_private.latch_absent(p_match_id, v_board.phase_started_at);
  select min(round) into v_next from public.wavelength_rounds where match_id = p_match_id and status = 'pending' and round > p_round;
  if v_next is not null then
    update public.wavelength_matches set current_round = v_next, phase = 'guess', phase_deadline = now() + make_interval(secs => (wavelength_private.config() ->> 'guess_seconds')::int), phase_started_at = now() where match_id = p_match_id;
    update public.wavelength_rounds set status = 'open' where match_id = p_match_id and round = v_next;
  else
    perform wavelength_private.finish_if_ready(p_match_id);
  end if;
end;
$$;

-- Only clues for rounds still waiting to be guessed gate the fill phase.  A
-- skipped earlier round must not prevent a later sudden-death pair opening.
create or replace function wavelength.submit_clue(p_match_id uuid, p_round integer, p_clue text)
returns wavelength.board language plpgsql security definer set search_path = '' as $$
declare v_user uuid := auth.uid(); v_board public.wavelength_matches; v_clue text := btrim(coalesce(p_clue, '')); v_cfg jsonb := wavelength_private.config();
begin
  if v_user is null then raise exception 'not_authenticated' using errcode = '42501'; end if;
  select wm.* into v_board from public.wavelength_matches wm join public.matches m on m.id = wm.match_id where wm.match_id = p_match_id and m.status = 'playing'::public.match_status for update of wm;
  if not found then raise exception 'match_not_playing' using errcode = 'P0001'; end if;
  if not exists (select 1 from public.wavelength_players where match_id = p_match_id and user_id = v_user) then raise exception 'not_a_participant' using errcode = '42501'; end if;
  if v_board.phase <> 'fill' then raise exception 'clue_not_open' using errcode = 'P0001'; end if;
  if v_board.phase_deadline <= now() then raise exception 'clue_deadline_passed' using errcode = 'P0001'; end if;
  if not exists (select 1 from public.wavelength_rounds where match_id = p_match_id and round = p_round and psychic_id = v_user and status = 'pending') then raise exception 'not_psychic' using errcode = '42501'; end if;
  if v_clue = '' then raise exception 'clue_required' using errcode = 'P0001'; end if;
  if v_clue ~ '[0-9]' then raise exception 'clue_contains_digit' using errcode = 'P0001'; end if;
  if cardinality(regexp_split_to_array(v_clue, E'\\s+')) > (v_cfg ->> 'clue_max_words')::int then raise exception 'clue_too_many_words' using errcode = 'P0001'; end if;
  if char_length(v_clue) > (v_cfg ->> 'clue_max_chars')::int then raise exception 'clue_too_long' using errcode = 'P0001'; end if;
  insert into public.wavelength_clues (match_id, round, clue) values (p_match_id, p_round, v_clue) on conflict (match_id, round) do update set clue = excluded.clue;
  insert into public.wavelength_clue_statuses (match_id, round) values (p_match_id, p_round) on conflict (match_id, round) do nothing;
  if not exists (select 1 from public.wavelength_rounds r where r.match_id = p_match_id and r.status = 'pending' and not exists (select 1 from public.wavelength_clue_statuses s where s.match_id = r.match_id and s.round = r.round)) then
    update public.wavelength_matches set phase = 'guess', phase_deadline = now() + make_interval(secs => (v_cfg ->> 'guess_seconds')::int), phase_started_at = now() where match_id = p_match_id;
    update public.wavelength_rounds set status = 'open' where match_id = p_match_id and round = v_board.current_round;
  end if;
  return wavelength_private.board_of(p_match_id);
end;
$$;

-- A fill expiry can be the final action (for example, every clue missed), so
-- it needs the same resolver as a guessed final round.
create or replace function wavelength.tick(p_match_id uuid)
returns wavelength.board language plpgsql security definer set search_path = '' as $$
declare v_user uuid := auth.uid(); v_match public.matches; v_board public.wavelength_matches; v_round smallint; v_default integer := (wavelength_private.config() ->> 'scale_max')::integer / 2;
begin
  if v_user is null then raise exception 'not_authenticated' using errcode = '42501'; end if;
  select * into v_match from public.matches where id = p_match_id for update;
  if not found or v_match.status <> 'playing'::public.match_status then raise exception 'match_not_playing' using errcode = 'P0001'; end if;
  update public.wavelength_players set last_seen_at = now(), absent = false where match_id = p_match_id and user_id = v_user;
  if not found then raise exception 'not_a_participant' using errcode = '42501'; end if;
  select * into v_board from public.wavelength_matches where match_id = p_match_id for update;
  if v_board.phase_deadline is null or v_board.phase_deadline > now() then return wavelength_private.board_of(p_match_id); end if;
  if v_board.phase = 'fill' then
    update public.wavelength_rounds r set status = 'skipped', points = 0, revealed_target = t.target from public.wavelength_targets t where r.match_id = p_match_id and r.match_id = t.match_id and r.round = t.round and r.status = 'pending' and not exists (select 1 from public.wavelength_clue_statuses s where s.match_id = r.match_id and s.round = r.round);
    perform wavelength_private.latch_absent(p_match_id, v_board.phase_started_at);
    select min(round) into v_round from public.wavelength_rounds where match_id = p_match_id and status = 'pending';
    if v_round is null then perform wavelength_private.finish_if_ready(p_match_id);
    else
      update public.wavelength_matches set current_round = v_round, phase = 'guess', phase_deadline = now() + make_interval(secs => (wavelength_private.config() ->> 'guess_seconds')::int), phase_started_at = now() where match_id = p_match_id;
      update public.wavelength_rounds set status = 'open' where match_id = p_match_id and round = v_round;
    end if;
  elsif v_board.phase = 'guess' then
    perform wavelength_private.settle_guess(p_match_id, v_board.current_round, v_default);
  end if;
  return wavelength_private.board_of(p_match_id);
end;
$$;

revoke all on function wavelength_private.deal_sudden_death(uuid) from public, anon, authenticated;
revoke all on function wavelength_private.finish_if_ready(uuid) from public, anon, authenticated;
