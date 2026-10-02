-- Wavelength's clock is deliberately a polling expiry function: any seated
-- player may call tick, and being early (or racing another tick) is harmless.
-- The match row is the serialization point for both player actions and expiry.

alter table public.wavelength_matches
  add column phase_started_at timestamptz not null default now();

-- The dealer creates the initial fill window, so it also starts the first
-- presence window.  Keeping this explicit avoids deriving presence from a
-- tunable deadline duration.
create or replace function wavelength_private.deal_board(
  p_match_id uuid,
  p_mode     text,
  p_preset   text default null,
  p_seed     double precision default null
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_cfg     jsonb := wavelength_private.config();
  v_seed    double precision := coalesce(p_seed, random());
  v_scale   int := (v_cfg ->> 'scale_max')::int;
  v_margin  int := (v_cfg ->> 'wedge_width')::int * 5 / 2;
  v_rounds  int;
  v_n       int;
  v_cycle   uuid[];
  v_team0   uuid[];
  v_team1   uuid[];
  v_used    int[] := '{}';
  v_card    record;
  v_i       int;
  v_psychic uuid;
  v_guesser uuid;
begin
  if p_mode is null or p_mode not in ('versus', 'coop') then raise exception 'invalid_mode' using errcode = 'P0001'; end if;
  if p_mode = 'coop' then
    if p_preset is null or not (v_cfg -> 'presets') ? p_preset then raise exception 'invalid_preset' using errcode = 'P0001'; end if;
    v_rounds := (v_cfg -> 'presets' -> p_preset ->> 'rounds')::int;
  else
    if p_preset is not null then raise exception 'invalid_preset' using errcode = 'P0001'; end if;
    v_rounds := (v_cfg ->> 'versus_rounds')::int;
  end if;
  select count(*) into v_n from public.run_participants rp join public.matches m on m.run_id = rp.run_id where m.id = p_match_id;
  if (p_mode = 'versus' and v_n <> 4) or (p_mode = 'coop' and v_n <> 2) then raise exception 'player_count_mismatch' using errcode = 'P0001'; end if;
  perform setseed(v_seed); set local max_parallel_workers_per_gather = 0;
  insert into public.wavelength_players (match_id, user_id, seat, team)
  select p_match_id, s.user_id, s.seat, case when p_mode = 'coop' then 0 else ((row_number() over (order by s.r) - 1) / 2)::smallint end
  from (select rp.user_id, rp.seat, random() as r from public.run_participants rp join public.matches m on m.run_id = rp.run_id where m.id = p_match_id) s;
  if p_mode = 'versus' then
    select array_agg(user_id order by seat) into v_team0 from public.wavelength_players where match_id = p_match_id and team = 0;
    select array_agg(user_id order by seat) into v_team1 from public.wavelength_players where match_id = p_match_id and team = 1;
    v_cycle := array[v_team0[1], v_team1[1], v_team0[2], v_team1[2]];
  else select array_agg(user_id order by seat) into v_cycle from public.wavelength_players where match_id = p_match_id; end if;
  for v_i in 1 .. v_rounds loop
    v_psychic := v_cycle[(v_i - 1) % array_length(v_cycle, 1) + 1];
    select wp.user_id into v_guesser from public.wavelength_players wp where wp.match_id = p_match_id and wp.user_id <> v_psychic and wp.team = (select team from public.wavelength_players where match_id = p_match_id and user_id = v_psychic);
    insert into public.wavelength_rounds (match_id, round, psychic_id, guesser_id) values (p_match_id, v_i, v_psychic, v_guesser);
    select d.card_id, d.left_label, d.right_label into v_card from wavelength_private.deck d where d.card_id <> all (v_used) order by random() limit 1;
    if not found then raise exception 'deck_exhausted' using errcode = 'P0001'; end if;
    v_used := v_used || v_card.card_id;
    insert into public.wavelength_cards (match_id, round, card_id, left_label, right_label) values (p_match_id, v_i, v_card.card_id, v_card.left_label, v_card.right_label);
    insert into public.wavelength_targets (match_id, round, target) values (p_match_id, v_i, v_margin + floor(random() * (v_scale - 2 * v_margin + 1))::int);
  end loop;
  insert into public.wavelength_matches (match_id, mode, preset, round_count, current_round, phase, phase_deadline, phase_started_at)
  values (p_match_id, p_mode, p_preset, v_rounds, 1, 'fill', now() + make_interval(secs => (v_rounds / v_n) * (v_cfg ->> 'fill_seconds_per_clue')::int), now());
end;
$$;

create function wavelength_private.latch_absent(p_match_id uuid, p_started_at timestamptz)
returns void language sql security definer set search_path = '' as $$
  update public.wavelength_players
     set absent = true
   where match_id = p_match_id and not absent and last_seen_at < p_started_at;
$$;

-- The one settlement path is shared by a click and an expired guess.  A
-- timeout therefore reveals and scores exactly like an ordinary lock.
create function wavelength_private.settle_guess(p_match_id uuid, p_round smallint, p_position integer)
returns void language plpgsql security definer set search_path = '' as $$
declare
  v_board public.wavelength_matches;
  v_target smallint;
  v_width integer := (wavelength_private.config() ->> 'wedge_width')::integer;
  v_points smallint;
  v_next smallint;
begin
  select * into v_board from public.wavelength_matches where match_id = p_match_id;
  select target into v_target from public.wavelength_targets where match_id = p_match_id and round = p_round;
  v_points := case when abs(p_position - v_target) <= v_width / 2 then 4 when abs(p_position - v_target) <= v_width * 3 / 2 then 3 when abs(p_position - v_target) <= v_width * 5 / 2 then 2 else 0 end;
  update public.wavelength_rounds set status = 'locked', points = v_points, revealed_target = v_target where match_id = p_match_id and round = p_round;
  perform wavelength_private.latch_absent(p_match_id, v_board.phase_started_at);
  select min(round) into v_next from public.wavelength_rounds
   where match_id = p_match_id and status = 'pending' and round > p_round;
  if v_next is not null then
    update public.wavelength_matches set current_round = v_next, phase = 'guess', phase_deadline = now() + make_interval(secs => (wavelength_private.config() ->> 'guess_seconds')::int), phase_started_at = now() where match_id = p_match_id;
    update public.wavelength_rounds set status = 'open' where match_id = p_match_id and round = v_next;
  else
    update public.wavelength_matches set phase = 'reveal', phase_deadline = null, phase_started_at = now() where match_id = p_match_id;
  end if;
end;
$$;

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
  if not exists (select 1 from public.wavelength_rounds where match_id = p_match_id and round = p_round and psychic_id = v_user) then raise exception 'not_psychic' using errcode = '42501'; end if;
  if v_clue = '' then raise exception 'clue_required' using errcode = 'P0001'; end if;
  if v_clue ~ '[0-9]' then raise exception 'clue_contains_digit' using errcode = 'P0001'; end if;
  if cardinality(regexp_split_to_array(v_clue, E'\\s+')) > (v_cfg ->> 'clue_max_words')::int then raise exception 'clue_too_many_words' using errcode = 'P0001'; end if;
  if char_length(v_clue) > (v_cfg ->> 'clue_max_chars')::int then raise exception 'clue_too_long' using errcode = 'P0001'; end if;
  insert into public.wavelength_clues (match_id, round, clue) values (p_match_id, p_round, v_clue) on conflict (match_id, round) do update set clue = excluded.clue;
  insert into public.wavelength_clue_statuses (match_id, round) values (p_match_id, p_round) on conflict (match_id, round) do nothing;
  if not exists (select 1 from public.wavelength_rounds r where r.match_id = p_match_id and not exists (select 1 from public.wavelength_clue_statuses s where s.match_id = r.match_id and s.round = r.round)) then
    update public.wavelength_matches set phase = 'guess', phase_deadline = now() + make_interval(secs => (v_cfg ->> 'guess_seconds')::int), phase_started_at = now() where match_id = p_match_id;
    update public.wavelength_rounds set status = 'open' where match_id = p_match_id and round = v_board.current_round;
  end if;
  return wavelength_private.board_of(p_match_id);
end;
$$;

create or replace function wavelength.lock_guess(p_match_id uuid, p_round integer, p_position integer)
returns wavelength.board language plpgsql security definer set search_path = '' as $$
declare v_user uuid := auth.uid(); v_board public.wavelength_matches; v_scale integer := (wavelength_private.config() ->> 'scale_max')::integer;
begin
  if v_user is null then raise exception 'not_authenticated' using errcode = '42501'; end if;
  if p_position is null or p_position not between 0 and v_scale then raise exception 'position_out_of_range' using errcode = 'P0001'; end if;
  select wm.* into v_board from public.wavelength_matches wm join public.matches m on m.id = wm.match_id where wm.match_id = p_match_id and m.status = 'playing'::public.match_status for update of wm;
  if not found then raise exception 'match_not_playing' using errcode = 'P0001'; end if;
  if not exists (select 1 from public.wavelength_players where match_id = p_match_id and user_id = v_user) then raise exception 'not_a_participant' using errcode = '42501'; end if;
  if v_board.phase <> 'guess' or v_board.current_round <> p_round then raise exception 'guess_not_open' using errcode = 'P0001'; end if;
  if v_board.phase_deadline <= now() then raise exception 'guess_deadline_passed' using errcode = 'P0001'; end if;
  if not exists (select 1 from public.wavelength_rounds where match_id = p_match_id and round = p_round and status = 'open' and guesser_id = v_user) then raise exception 'not_guesser' using errcode = '42501'; end if;
  perform wavelength_private.settle_guess(p_match_id, p_round::smallint, p_position);
  return wavelength_private.board_of(p_match_id);
end;
$$;

create function wavelength.tick(p_match_id uuid)
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
    if v_round is null then update public.wavelength_matches set phase = 'reveal', phase_deadline = null, phase_started_at = now() where match_id = p_match_id;
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

-- Pause/resume owns absolute deadlines for every timed game.
create or replace function public.resume_match(p_match_id uuid)
returns public.matches language plpgsql security definer set search_path = '' as $$
declare v_user uuid := auth.uid(); v_match public.matches; v_run public.runs; v_lobby public.lobbies; v_elapsed interval;
begin
  if v_user is null or (auth.jwt() ->> 'is_anonymous')::boolean is true then raise exception 'not_authenticated' using errcode = '42501'; end if;
  select * into v_match from public.matches where id = p_match_id for update; if not found then raise exception 'match_not_found' using errcode = 'P0001'; end if;
  select * into v_run from public.runs where id = v_match.run_id; if v_run.lobby_id is null then raise exception 'no_host' using errcode = '42501'; end if;
  select * into v_lobby from public.lobbies where id = v_run.lobby_id for update; if v_lobby.host_id <> v_user then raise exception 'not_host' using errcode = '42501'; end if;
  if not exists (select 1 from public.lobby_members where lobby_id = v_lobby.id and user_id = v_user and left_at is null) then raise exception 'not_a_member' using errcode = '42501'; end if;
  if v_match.status <> 'paused'::public.match_status then raise exception 'match_not_paused' using errcode = 'P0001'; end if;
  v_elapsed := now() - v_match.paused_at;
  case v_match.game when 'auction_team_builder' then update public.auction_matches set turn_deadline = turn_deadline + v_elapsed, phase_deadline = phase_deadline + v_elapsed where match_id = p_match_id;
    when 'higher_or_lower' then update public.higher_or_lower_matches set phase_deadline = phase_deadline + v_elapsed where match_id = p_match_id;
    when 'sabotage_draft' then update public.sabotage_draft_matches set pick_deadline = pick_deadline + v_elapsed, guess_deadline = guess_deadline + v_elapsed where match_id = p_match_id;
    when 'wavelength_2v2' then update public.wavelength_matches set phase_deadline = phase_deadline + v_elapsed, phase_started_at = phase_started_at + v_elapsed where match_id = p_match_id;
  end case;
  update public.matches set status = 'playing'::public.match_status, paused_at = null where id = p_match_id returning * into v_match; return v_match;
end;
$$;

revoke all on function wavelength_private.latch_absent(uuid, timestamptz) from public, anon, authenticated;
revoke all on function wavelength_private.settle_guess(uuid, smallint, integer) from public, anon, authenticated;
revoke all on function wavelength.tick(uuid) from public, anon;
grant execute on function wavelength.tick(uuid) to authenticated;
