-- Sabotage draft: the public guessing window and its two distinct hits.
--
-- A name-only hit re-spins the hidden card; an exact hit replaces it with the
-- card the guesser supplied.  The match row is locked for every transition
-- and every guess, so two racers cannot both claim the one hit of a kind a
-- slot may take in a round.

alter table public.sabotage_draft_matches
  add column guess_deadline timestamptz;

alter type sabotage_draft.round add attribute guess_deadline timestamptz;

create type sabotage_draft.guess_result as enum ('miss', 'respun', 'sabotaged');

create table public.sabotage_draft_guesses (
  match_id uuid not null references public.matches (id) on delete cascade,
  round_number smallint not null,
  user_id uuid not null,
  target_user_id uuid not null,
  player_id text not null,
  season smallint,
  replacement_player_id text,
  replacement_season smallint,
  result sabotage_draft.guess_result not null,
  created_at timestamptz not null default now(),

  primary key (match_id, round_number, user_id),
  foreign key (match_id, user_id)
    references public.sabotage_draft_players (match_id, user_id) on delete cascade,
  foreign key (match_id, target_user_id)
    references public.sabotage_draft_players (match_id, user_id) on delete cascade,
  check (user_id <> target_user_id),
  check (
    (season is null and replacement_player_id is null and replacement_season is null)
    or
    (season is not null and replacement_player_id is not null and replacement_season is not null)
  )
);

-- This table is deliberately a tiny state machine rather than a count of
-- successful guesses.  Its primary key makes each kind of hit unique even
-- when a later guess sees a card already changed by an earlier one.
create table public.sabotage_draft_pick_hits (
  match_id uuid not null references public.matches (id) on delete cascade,
  round_number smallint not null,
  target_user_id uuid not null,
  kind text not null check (kind in ('respin', 'sabotage')),
  guesser_user_id uuid not null,
  created_at timestamptz not null default now(),

  primary key (match_id, round_number, target_user_id, kind),
  foreign key (match_id, target_user_id)
    references public.sabotage_draft_players (match_id, user_id) on delete cascade,
  foreign key (match_id, guesser_user_id)
    references public.sabotage_draft_players (match_id, user_id) on delete cascade
);

create or replace function sabotage_draft_private.round_of(p_match_id uuid)
returns sabotage_draft.round
language sql stable security definer set search_path = '' as $$
  select (m.match_id, m.round_count, m.current_round, r.slot, r.franchise_code,
          m.pick_deadline, now(), m.guess_deadline)::sabotage_draft.round
    from public.sabotage_draft_matches m
    join public.sabotage_draft_rounds r
      on r.match_id = m.match_id and r.round_number = m.current_round
   where m.match_id = p_match_id;
$$;

create function sabotage_draft_private.open_guess_window(p_match_id uuid)
returns void
language sql security definer set search_path = '' as $$
  update public.sabotage_draft_matches
     set pick_deadline = null, guess_deadline = now() + interval '30 seconds'
   where match_id = p_match_id;
$$;

-- All non-final rounds immediately enter the next simultaneous pick window.
-- The final roster/scoring ticket owns what happens after round fourteen, so
-- this migration only closes its guess window rather than inventing an end.
create function sabotage_draft_private.advance_round(p_match_id uuid)
returns void
language plpgsql security definer set search_path = '' as $$
declare v_round smallint;
begin
  select current_round into v_round
    from public.sabotage_draft_matches where match_id = p_match_id;
  if v_round < 14 then
    update public.sabotage_draft_matches
       set current_round = v_round + 1,
           pick_deadline = now() + interval '45 seconds',
           guess_deadline = null
     where match_id = p_match_id;
  else
    update public.sabotage_draft_matches
       set pick_deadline = null, guess_deadline = null
     where match_id = p_match_id;
  end if;
end;
$$;

-- Replace 0052's close-only behavior with the state transition into guesses.
create or replace function sabotage_draft.submit_pick(
  p_match_id uuid, p_player_id text, p_season smallint
)
returns public.sabotage_draft_picks
language plpgsql security definer set search_path = '' as $$
declare
  v_user uuid := auth.uid(); v_board public.sabotage_draft_matches;
  v_round public.sabotage_draft_rounds; v_pick public.sabotage_draft_picks; v_name text;
begin
  if v_user is null then raise exception 'not_authenticated' using errcode = '42501'; end if;
  select sm.* into v_board from public.sabotage_draft_matches sm join public.matches mt on mt.id = sm.match_id
   where sm.match_id = p_match_id and mt.status = 'playing'::public.match_status for update of sm;
  if not found then raise exception 'match_not_playing' using errcode = 'P0001'; end if;
  if not exists (select 1 from public.sabotage_draft_players where match_id = p_match_id and user_id = v_user) then
    raise exception 'not_a_participant' using errcode = '42501'; end if;
  if v_board.pick_deadline is null or v_board.pick_deadline <= now() then raise exception 'pick_window_closed' using errcode = 'P0001'; end if;
  if sabotage_draft_private.has_picked(p_match_id, v_board.current_round, v_user) then raise exception 'already_picked' using errcode = 'P0001'; end if;
  select * into v_round from public.sabotage_draft_rounds where match_id = p_match_id and round_number = v_board.current_round;
  select display_name into v_name from private.av_roster_players
   where franchise_code = v_round.franchise_code and player_id = p_player_id and season = p_season
     and slot_category = any(sabotage_draft_private.pool_categories(v_round.slot));
  if not found then raise exception 'invalid_pick' using errcode = 'P0001'; end if;
  insert into public.sabotage_draft_picks (match_id, round_number, user_id, player_id, display_name, season, by_timeout)
  values (p_match_id, v_board.current_round, v_user, p_player_id, v_name, p_season, false) returning * into v_pick;
  insert into public.sabotage_draft_pick_statuses (match_id, round_number, user_id) values (p_match_id, v_board.current_round, v_user);
  if sabotage_draft_private.all_picked(p_match_id, v_board.current_round) then perform sabotage_draft_private.open_guess_window(p_match_id); end if;
  return v_pick;
end;
$$;

create or replace function sabotage_draft_private.expire(p_match_id uuid)
returns boolean
language plpgsql security definer set search_path = '' as $$
declare
  v_board public.sabotage_draft_matches; v_round public.sabotage_draft_rounds;
  v_missing record; v_drawn record;
begin
  select sm.* into v_board from public.sabotage_draft_matches sm join public.matches mt on mt.id = sm.match_id
   where sm.match_id = p_match_id and mt.status = 'playing'::public.match_status for update of sm;
  if not found then return false; end if;
  if v_board.pick_deadline is not null and v_board.pick_deadline <= now() then
    select * into v_round from public.sabotage_draft_rounds where match_id = p_match_id and round_number = v_board.current_round;
    for v_missing in select sp.user_id from public.sabotage_draft_players sp where sp.match_id = p_match_id
      and not sabotage_draft_private.has_picked(p_match_id, v_board.current_round, sp.user_id) loop
      select * into v_drawn from sabotage_draft_private.random_pick(v_round.franchise_code, sabotage_draft_private.pool_categories(v_round.slot));
      if not found then raise exception 'pool_exhausted' using errcode = 'P0001'; end if;
      insert into public.sabotage_draft_picks (match_id, round_number, user_id, player_id, display_name, season, by_timeout)
      values (p_match_id, v_board.current_round, v_missing.user_id, v_drawn.player_id, v_drawn.display_name, v_drawn.season, true);
      insert into public.sabotage_draft_pick_statuses (match_id, round_number, user_id) values (p_match_id, v_board.current_round, v_missing.user_id);
    end loop;
    perform sabotage_draft_private.open_guess_window(p_match_id);
    return true;
  end if;
  if v_board.guess_deadline is not null and v_board.guess_deadline <= now() then
    perform sabotage_draft_private.advance_round(p_match_id);
    return true;
  end if;
  return false;
end;
$$;

create function sabotage_draft.submit_guess(
  p_match_id uuid, p_target_user_id uuid, p_player_id text, p_season smallint default null,
  p_replacement_player_id text default null, p_replacement_season smallint default null
)
returns public.sabotage_draft_guesses
language plpgsql security definer set search_path = '' as $$
declare
  v_user uuid := auth.uid(); v_board public.sabotage_draft_matches; v_round public.sabotage_draft_rounds;
  v_pick public.sabotage_draft_picks; v_drawn record; v_guess public.sabotage_draft_guesses; v_replacement_name text;
  v_exact boolean; v_kind text; v_result sabotage_draft.guess_result;
begin
  if v_user is null then raise exception 'not_authenticated' using errcode = '42501'; end if;
  if (p_season is null) <> (p_replacement_player_id is null) or (p_season is null) <> (p_replacement_season is null) then
    raise exception 'invalid_guess_shape' using errcode = 'P0001'; end if;
  select sm.* into v_board from public.sabotage_draft_matches sm join public.matches mt on mt.id = sm.match_id
   where sm.match_id = p_match_id and mt.status = 'playing'::public.match_status for update of sm;
  if not found then raise exception 'match_not_playing' using errcode = 'P0001'; end if;
  if not exists (select 1 from public.sabotage_draft_players where match_id = p_match_id and user_id = v_user) then raise exception 'not_a_participant' using errcode = '42501'; end if;
  if v_user = p_target_user_id or not exists (select 1 from public.sabotage_draft_players where match_id = p_match_id and user_id = p_target_user_id) then raise exception 'invalid_target' using errcode = 'P0001'; end if;
  if v_board.guess_deadline is null or v_board.guess_deadline <= now() then raise exception 'guess_window_closed' using errcode = 'P0001'; end if;
  if exists (select 1 from public.sabotage_draft_guesses where match_id = p_match_id and round_number = v_board.current_round and user_id = v_user) then raise exception 'already_guessed' using errcode = 'P0001'; end if;
  select * into v_round from public.sabotage_draft_rounds where match_id = p_match_id and round_number = v_board.current_round;
  if not exists (select 1 from private.av_roster_players where franchise_code = v_round.franchise_code and player_id = p_player_id and slot_category = any(sabotage_draft_private.pool_categories(v_round.slot))) then raise exception 'invalid_guess' using errcode = 'P0001'; end if;
  if p_season is not null then
    select display_name into v_replacement_name from private.av_roster_players where franchise_code = v_round.franchise_code and player_id = p_replacement_player_id and season = p_replacement_season and slot_category = any(sabotage_draft_private.pool_categories(v_round.slot));
    if not found then raise exception 'invalid_replacement' using errcode = 'P0001'; end if;
  end if;
  select * into v_pick from public.sabotage_draft_picks where match_id = p_match_id and round_number = v_board.current_round and user_id = p_target_user_id;
  v_exact := v_pick.player_id = p_player_id and (p_season is null or v_pick.season = p_season);
  v_kind := case when p_season is null then 'respin' else 'sabotage' end;
  if v_exact and not exists (select 1 from public.sabotage_draft_pick_hits where match_id = p_match_id and round_number = v_board.current_round and target_user_id = p_target_user_id and kind = v_kind) then
    insert into public.sabotage_draft_pick_hits (match_id, round_number, target_user_id, kind, guesser_user_id) values (p_match_id, v_board.current_round, p_target_user_id, v_kind, v_user);
    if v_kind = 'respin' then
      select * into v_drawn from sabotage_draft_private.random_pick(v_round.franchise_code, sabotage_draft_private.pool_categories(v_round.slot));
      update public.sabotage_draft_picks set player_id = v_drawn.player_id, display_name = v_drawn.display_name, season = v_drawn.season, by_timeout = false
       where match_id = p_match_id and round_number = v_board.current_round and user_id = p_target_user_id;
      v_result := 'respun';
    else
      update public.sabotage_draft_picks set player_id = p_replacement_player_id, display_name = v_replacement_name, season = p_replacement_season, by_timeout = false
       where match_id = p_match_id and round_number = v_board.current_round and user_id = p_target_user_id;
      v_result := 'sabotaged';
    end if;
  else
    v_result := 'miss';
  end if;
  insert into public.sabotage_draft_guesses (match_id, round_number, user_id, target_user_id, player_id, season, replacement_player_id, replacement_season, result)
  values (p_match_id, v_board.current_round, v_user, p_target_user_id, p_player_id, p_season, p_replacement_player_id, p_replacement_season, v_result) returning * into v_guess;
  return v_guess;
end;
$$;

create or replace function sabotage_draft_private.sweep()
returns void language plpgsql security definer set search_path = '' as $$
declare r record;
begin
  for r in select sm.match_id from public.sabotage_draft_matches sm join public.matches mt on mt.id = sm.match_id
    where mt.status = 'playing'::public.match_status and (sm.pick_deadline < now() - interval '2 seconds' or sm.guess_deadline < now() - interval '2 seconds') loop
    perform sabotage_draft_private.expire(r.match_id);
  end loop;
end;
$$;

alter table public.sabotage_draft_guesses enable row level security;
alter table public.sabotage_draft_pick_hits enable row level security;
create policy sabotage_draft_guesses_select_member on public.sabotage_draft_guesses for select to authenticated using (private.is_match_member(match_id));
create policy sabotage_draft_pick_hits_select_member on public.sabotage_draft_pick_hits for select to authenticated using (private.is_match_member(match_id));
grant select on public.sabotage_draft_guesses, public.sabotage_draft_pick_hits to authenticated;
alter publication supabase_realtime add table public.sabotage_draft_guesses;
alter publication supabase_realtime add table public.sabotage_draft_pick_hits;

revoke all on function sabotage_draft_private.open_guess_window(uuid), sabotage_draft_private.advance_round(uuid) from public, anon, authenticated;
revoke all on function sabotage_draft.submit_guess(uuid, uuid, text, smallint, text, smallint) from public, anon;
grant execute on function sabotage_draft.submit_guess(uuid, uuid, text, smallint, text, smallint) to authenticated;
