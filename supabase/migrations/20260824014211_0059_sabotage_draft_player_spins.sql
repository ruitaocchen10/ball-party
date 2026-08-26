-- Sabotage draft: every seated player spins their own franchise each round,
-- not one shared spin for the table. See docs/games/sabotage_draft.md.
--
-- 0051 built the team spin as a single row per (match_id, round_number),
-- shared by every player. That was a misreading of the intended design: with
-- N seated players, a round should draw N independent franchises -- one per
-- player -- and a guess is always aimed at one specific target's spin, never
-- at "the round's" spin. Nothing about visibility changes: a spin is still
-- public to the whole table (including future rounds), exactly as 0051's own
-- header argued for the old shared column. Only WHO a spin belongs to is new.
--
-- This is a breaking schema change to sabotage_draft_rounds, not a backfill.
-- The game has not shipped -- only test-fixture matches exist -- so an
-- in-flight match dealt before this migration simply has no franchise data
-- to read afterward. That is an acceptable clean cut, not something this
-- migration tries to paper over.
--
-- `sabotage_draft_rounds` keeps only what is genuinely round-wide: the fixed
-- (or, for round 14, widened) slot. The franchise moves to a new table, the
-- same split 0052 already makes between a pick's identity and pick presence:
-- `sabotage_draft_round_spins` is one row per (round, player), the same
-- "visible to everyone, secret to no one" table sabotage_draft_rounds was.

alter table public.sabotage_draft_rounds drop column franchise_code;

create table public.sabotage_draft_round_spins (
  match_id       uuid     not null references public.matches (id) on delete cascade,
  round_number   smallint not null,
  user_id        uuid     not null,
  franchise_code text     not null,

  primary key (match_id, round_number, user_id),
  foreign key (match_id, round_number)
    references public.sabotage_draft_rounds (match_id, round_number),
  foreign key (match_id, user_id)
    references public.sabotage_draft_players (match_id, user_id) on delete cascade
);

alter table public.sabotage_draft_round_spins enable row level security;

create policy sabotage_draft_round_spins_select_member on public.sabotage_draft_round_spins
  for select to authenticated using (private.is_match_member(match_id));

grant select on public.sabotage_draft_round_spins to authenticated;

alter publication supabase_realtime add table public.sabotage_draft_round_spins;

-- The projection a client is told about the match no longer has one
-- table-wide franchise to report -- see sabotage_draft.options below for how
-- a client asks "what's so-and-so's spin" instead.
alter type sabotage_draft.round drop attribute franchise_code;

-- ------------------------------------------------------------------ spins --

-- The one-row lookup every pick/guess/expiry path below needs: what did this
-- player spin for this round. Centralized here instead of inlined at each
-- call site, the same reason sabotage_draft_private.random_pick is its own
-- function rather than copy-pasted.
create function sabotage_draft_private.spin_franchise(
  p_match_id uuid, p_round smallint, p_user_id uuid
)
returns text
language sql
stable
security definer
set search_path = ''
as $$
  select franchise_code from public.sabotage_draft_round_spins
   where match_id = p_match_id and round_number = p_round and user_id = p_user_id;
$$;

-- --------------------------------------------------------------- the deal --

-- Unchanged rounds/slots loop; the franchise draw moves inside a nested loop
-- over every seated player, run once per (round, player) instead of once per
-- round. No exclusion set here either -- the design doc's "a franchise can be
-- spun more than once" already covers a repeat across rounds, and nothing
-- says two players can't spin the same franchise the same round.
create or replace function sabotage_draft_private.deal_board(
  p_match_id uuid,
  p_seed double precision default null
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_seed  double precision := coalesce(p_seed, random());
  v_n     int;
  v_i     smallint;
  v_slot  text;
  v_franchise text;
  v_player record;
  v_slots constant text[] := array[
    'QB', 'RB1', 'RB2', 'WR1', 'WR2', 'WR3', 'TE',
    'OL', 'DL', 'LB', 'CB', 'S', 'ST'
  ];
begin
  perform setseed(v_seed);
  set local max_parallel_workers_per_gather = 0;

  insert into public.sabotage_draft_players (match_id, user_id, seat)
  select p_match_id, rp.user_id, rp.seat
    from public.run_participants rp
    join public.matches m on m.run_id = rp.run_id
   where m.id = p_match_id;

  select count(*) into v_n from public.sabotage_draft_players where match_id = p_match_id;

  if v_n < 2 then
    raise exception 'too_few_players' using errcode = 'P0001';
  end if;

  for v_i in 1 .. 14 loop
    v_slot := case when v_i <= 13 then v_slots[v_i] else 'X_FACTOR' end;

    insert into public.sabotage_draft_rounds (match_id, round_number, slot)
    values (p_match_id, v_i, v_slot);

    for v_player in
      select sp.user_id from public.sabotage_draft_players sp
       where sp.match_id = p_match_id
       order by sp.seat
    loop
      select r.franchise_code into v_franchise
        from private.av_roster_players r
       where r.slot_category = any(sabotage_draft_private.pool_categories(v_slot))
       group by r.franchise_code
       order by random()
       limit 1;

      if not found then
        raise exception 'pool_exhausted' using errcode = 'P0001';
      end if;

      insert into public.sabotage_draft_round_spins (match_id, round_number, user_id, franchise_code)
      values (p_match_id, v_i, v_player.user_id, v_franchise);
    end loop;
  end loop;

  insert into public.sabotage_draft_matches (match_id, round_count, current_round, pick_deadline)
  values (p_match_id, 14, 1, now() + interval '45 seconds');

  insert into sabotage_draft_private.boards (match_id, seed) values (p_match_id, v_seed);
end;
$$;

create or replace function sabotage_draft_private.round_of(p_match_id uuid)
returns sabotage_draft.round
language sql stable security definer set search_path = '' as $$
  select (m.match_id, m.round_count, m.current_round, r.slot,
          m.pick_deadline, now(), m.guess_deadline, m.x_factor_open)::sabotage_draft.round
    from public.sabotage_draft_matches m
    join public.sabotage_draft_rounds r
      on r.match_id = m.match_id and r.round_number = m.current_round
   where m.match_id = p_match_id;
$$;

-- -------------------------------------------------------------------- picks --

-- Resolve the franchise against the caller's OWN spin, not a shared round.
create or replace function sabotage_draft.submit_pick(
  p_match_id uuid, p_player_id text, p_season smallint
)
returns public.sabotage_draft_picks
language plpgsql security definer set search_path = '' as $$
declare
  v_user uuid := auth.uid(); v_board public.sabotage_draft_matches;
  v_round public.sabotage_draft_rounds; v_franchise text; v_pick public.sabotage_draft_picks; v_name text;
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
  v_franchise := sabotage_draft_private.spin_franchise(p_match_id, v_board.current_round, v_user);
  select display_name into v_name from private.av_roster_players
   where franchise_code = v_franchise and player_id = p_player_id and season = p_season
     and slot_category = any(sabotage_draft_private.pool_categories(v_round.slot));
  if not found then raise exception 'invalid_pick' using errcode = 'P0001'; end if;
  insert into public.sabotage_draft_picks (match_id, round_number, user_id, player_id, display_name, season, by_timeout)
  values (p_match_id, v_board.current_round, v_user, p_player_id, v_name, p_season, false) returning * into v_pick;
  insert into public.sabotage_draft_pick_statuses (match_id, round_number, user_id) values (p_match_id, v_board.current_round, v_user);
  if sabotage_draft_private.all_picked(p_match_id, v_board.current_round) then perform sabotage_draft_private.open_guess_window(p_match_id); end if;
  return v_pick;
end;
$$;

-- ------------------------------------------------------------------- timer --

-- Each missing player is substituted from THEIR OWN spin -- the franchise
-- lookup moves inside the loop instead of being read once for the round.
create or replace function sabotage_draft_private.expire(p_match_id uuid)
returns boolean
language plpgsql security definer set search_path = '' as $$
declare
  v_board public.sabotage_draft_matches; v_round public.sabotage_draft_rounds;
  v_missing record; v_drawn record; v_franchise text;
begin
  select sm.* into v_board from public.sabotage_draft_matches sm join public.matches mt on mt.id = sm.match_id
   where sm.match_id = p_match_id and mt.status = 'playing'::public.match_status for update of sm;
  if not found then return false; end if;
  if v_board.pick_deadline is not null and v_board.pick_deadline <= now() then
    select * into v_round from public.sabotage_draft_rounds where match_id = p_match_id and round_number = v_board.current_round;
    for v_missing in select sp.user_id from public.sabotage_draft_players sp where sp.match_id = p_match_id
      and not sabotage_draft_private.has_picked(p_match_id, v_board.current_round, sp.user_id) loop
      v_franchise := sabotage_draft_private.spin_franchise(p_match_id, v_board.current_round, v_missing.user_id);
      select * into v_drawn from sabotage_draft_private.random_pick(v_franchise, sabotage_draft_private.pool_categories(v_round.slot));
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

-- ------------------------------------------------------------------ guesses --

-- Resolve the franchise against the TARGET's spin, not the guesser's --
-- sabotaging someone means knowing their pool, not your own.
create or replace function sabotage_draft.submit_guess(
  p_match_id uuid, p_target_user_id uuid, p_player_id text, p_season smallint default null,
  p_replacement_player_id text default null, p_replacement_season smallint default null
)
returns public.sabotage_draft_guesses
language plpgsql security definer set search_path = '' as $$
declare
  v_user uuid := auth.uid(); v_board public.sabotage_draft_matches; v_round public.sabotage_draft_rounds;
  v_franchise text; v_pick public.sabotage_draft_picks; v_drawn record; v_guess public.sabotage_draft_guesses; v_replacement_name text;
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
  v_franchise := sabotage_draft_private.spin_franchise(p_match_id, v_board.current_round, p_target_user_id);
  if not exists (select 1 from private.av_roster_players where franchise_code = v_franchise and player_id = p_player_id and slot_category = any(sabotage_draft_private.pool_categories(v_round.slot))) then raise exception 'invalid_guess' using errcode = 'P0001'; end if;
  if p_season is not null then
    select display_name into v_replacement_name from private.av_roster_players where franchise_code = v_franchise and player_id = p_replacement_player_id and season = p_replacement_season and slot_category = any(sabotage_draft_private.pool_categories(v_round.slot));
    if not found then raise exception 'invalid_replacement' using errcode = 'P0001'; end if;
  end if;
  select * into v_pick from public.sabotage_draft_picks where match_id = p_match_id and round_number = v_board.current_round and user_id = p_target_user_id;
  v_exact := v_pick.player_id = p_player_id and (p_season is null or v_pick.season = p_season);
  v_kind := case when p_season is null then 'respin' else 'sabotage' end;
  if v_exact and not exists (select 1 from public.sabotage_draft_pick_hits where match_id = p_match_id and round_number = v_board.current_round and target_user_id = p_target_user_id and kind = v_kind) then
    insert into public.sabotage_draft_pick_hits (match_id, round_number, target_user_id, kind, guesser_user_id) values (p_match_id, v_board.current_round, p_target_user_id, v_kind, v_user);
    if v_kind = 'respin' then
      select * into v_drawn from sabotage_draft_private.random_pick(v_franchise, sabotage_draft_private.pool_categories(v_round.slot));
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

-- ----------------------------------------------------------------- options --

-- Adds p_target_user_id: eligible names now depend on whose spin they're
-- read against, defaulting to the caller's own (the pick case). A signature
-- change, not a body change, so this is drop-then-recreate rather than
-- create-or-replace.
drop function if exists sabotage_draft.options(uuid);

create function sabotage_draft.options(p_match_id uuid, p_target_user_id uuid default null)
returns table (player_id text, display_name text, season smallint, slot_category text)
language plpgsql stable security definer set search_path = '' as $$
declare v_round public.sabotage_draft_rounds; v_target uuid; v_franchise text;
begin
  if not private.is_match_member(p_match_id) then
    raise exception 'not_a_participant' using errcode = '42501';
  end if;
  v_target := coalesce(p_target_user_id, auth.uid());
  if not exists (select 1 from public.sabotage_draft_players where match_id = p_match_id and user_id = v_target) then
    raise exception 'invalid_target' using errcode = 'P0001';
  end if;
  select r.* into v_round from public.sabotage_draft_matches m
    join public.sabotage_draft_rounds r on r.match_id=m.match_id and r.round_number=m.current_round
    where m.match_id=p_match_id;
  v_franchise := sabotage_draft_private.spin_franchise(p_match_id, v_round.round_number, v_target);
  return query
    select p.player_id, p.display_name, p.season, p.slot_category
      from private.av_roster_players p
     where p.franchise_code=v_franchise
       and p.slot_category=any(sabotage_draft_private.pool_categories(v_round.slot))
     order by p.display_name, p.season;
end;
$$;

-- --------------------------------------------------------------- standings --

-- final_cards already carries each card's own round_number (14 for an
-- accepted X-Factor replacement, its original round otherwise), which is
-- exactly the (round, player) key a spin needs -- no more round-by-slot
-- lookup required to find it.
create or replace function sabotage_draft_private.roster_strengths(p_match_id uuid)
returns table (user_id uuid, roster_strength integer)
language sql stable security definer set search_path = '' as $$
  with final_cards as (
    select p.user_id,
           case when d.replace_slot = r.slot then x.player_id else p.player_id end as player_id,
           case when d.replace_slot = r.slot then x.season else p.season end as season,
           case when d.replace_slot = r.slot then 'X_FACTOR' else r.slot end as source_slot,
           case when d.replace_slot = r.slot then 14 else p.round_number end as source_round
      from public.sabotage_draft_picks p
      join public.sabotage_draft_rounds r on r.match_id = p.match_id and r.round_number = p.round_number
      join public.sabotage_draft_x_factor_decisions d on d.match_id = p.match_id and d.user_id = p.user_id
      join public.sabotage_draft_picks x on x.match_id = p.match_id and x.user_id = p.user_id and x.round_number = 14
     where p.match_id = p_match_id and p.round_number between 1 and 13
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
$$;

-- ---------------------------------------------------------------- privileges --

revoke all on function sabotage_draft_private.spin_franchise(uuid, smallint, uuid) from public, anon, authenticated;
revoke all on function sabotage_draft.options(uuid, uuid) from public, anon;
grant execute on function sabotage_draft.options(uuid, uuid) to authenticated;
