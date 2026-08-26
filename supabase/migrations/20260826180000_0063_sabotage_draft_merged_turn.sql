-- Sabotage draft: one shared clock per turn, not a pick window followed by a
-- guess window.
--
-- 0062 made a round turn-based but kept two sequential deadlines per turn:
-- the active seat picks against `pick_deadline`, and only once that pick
-- lands does `guess_deadline` open for everyone else. That is a needless
-- second wait -- there is nothing stopping another seat from naming a guess
-- the instant the turn starts, since the eligible pool (the active seat's
-- spun franchise) is public from the moment the turn opens, not from the
-- moment the pick lands. This migration merges both into one
-- `turn_deadline`: the active seat may lock their pick any time within it,
-- and every other seat may lock in exactly one action -- a guess or an
-- explicit pass -- any time within that same window, including before the
-- pick exists.
--
-- A guess made before the pick exists has nothing yet to check it against,
-- so it is recorded PENDING (`result` is now nullable; null means pending)
-- rather than resolved on the spot. Nothing resolves incrementally as
-- guesses trickle in -- the whole turn's guesses resolve in exactly one
-- batch, in submission order, the moment the turn's action set is complete:
-- the active seat has picked, and every other seat has either guessed or
-- passed. `sabotage_draft_private.resolve_turn` is that one batch, and it
-- is also the new sole caller of `advance_turn` -- there is no longer a
-- separate "guess window closed" transition distinct from "turn resolved."
--
-- PASS IS NEW SURFACE, ON PURPOSE. A guess remains optional -- naming a
-- random card you know nothing about is not a real choice -- but early
-- completion has to be able to tell "hasn't acted yet" from "chooses not
-- to act," and silence cannot carry that distinction. `submit_pass` is that
-- explicit signal, the same shape `auction_team_builder.pass_lot` already
-- gives the auction's own turn-based bidding. Disconnected players are
-- unaffected: an absent seat that neither guesses nor passes simply never
-- completes the turn early, and the shared `turn_deadline` remains the
-- backstop that ends it anyway -- exactly as an absent seat not guessing
-- already worked before this migration.

-- ------------------------------------------------------------------ clock --

alter table public.sabotage_draft_matches
  drop column pick_deadline,
  drop column guess_deadline,
  add column turn_deadline timestamptz;

alter type sabotage_draft.round drop attribute pick_deadline;
alter type sabotage_draft.round drop attribute guess_deadline;
alter type sabotage_draft.round add attribute turn_deadline timestamptz;

create or replace function sabotage_draft_private.round_of(p_match_id uuid)
returns sabotage_draft.round
language sql stable security definer set search_path = '' as $$
  select (m.match_id, m.round_count, m.current_round, r.slot,
          now(), m.x_factor_open,
          sabotage_draft_private.active_user(m.match_id, m.active_seat),
          m.turn_deadline)::sabotage_draft.round
    from public.sabotage_draft_matches m
    join public.sabotage_draft_rounds r
      on r.match_id = m.match_id and r.round_number = m.current_round
   where m.match_id = p_match_id;
$$;

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

  insert into public.sabotage_draft_matches (match_id, round_count, current_round, active_seat, turn_deadline)
  values (p_match_id, 14, 1, 0, now() + interval '45 seconds');

  insert into sabotage_draft_private.boards (match_id, seed) values (p_match_id, v_seed);
end;
$$;

-- ------------------------------------------------------------------ pass --

-- The explicit "I'm not guessing this turn" signal -- see the header for why
-- this has to exist rather than inferring it from silence. A pass is public
-- the same way a guess's existence (though not its content) already is:
-- everyone can see who has acted, not what they threw.
create table public.sabotage_draft_passes (
  match_id       uuid     not null references public.matches (id) on delete cascade,
  round_number   smallint not null,
  target_user_id uuid     not null,
  user_id        uuid     not null,
  created_at     timestamptz not null default now(),

  primary key (match_id, round_number, target_user_id, user_id),
  foreign key (match_id, target_user_id)
    references public.sabotage_draft_players (match_id, user_id) on delete cascade,
  foreign key (match_id, user_id)
    references public.sabotage_draft_players (match_id, user_id) on delete cascade,
  check (user_id <> target_user_id)
);

alter table public.sabotage_draft_passes enable row level security;

create policy sabotage_draft_passes_select_member on public.sabotage_draft_passes
  for select to authenticated using (private.is_match_member(match_id));

grant select on public.sabotage_draft_passes to authenticated;

alter publication supabase_realtime add table public.sabotage_draft_passes;

-- --------------------------------------------------------------- guesses --

-- NULL is now a real, meaningful state: a guess held pending, not yet known
-- to be a hit or a miss because the card it targets did not exist yet when
-- it was made.
alter table public.sabotage_draft_guesses alter column result drop not null;

-- Batched resolution has to process pending guesses in the order they were
-- actually made -- `created_at` cannot carry that: `now()` is stable for an
-- entire transaction, so two guesses submitted moments apart in the same
-- transaction (every pgTAP test; in principle any two RPC calls fast enough
-- to land in one) get the identical timestamp and an undefined tiebreak.
-- An identity column is a real, strictly increasing insertion order.
alter table public.sabotage_draft_guesses add column id bigint generated always as identity;

-- ------------------------------------------------------------------ turn --

-- Whether every action this turn needs has landed: the active seat's pick,
-- and one guess-or-pass from every other seated player. This is the single
-- question that decides early completion -- see the header for why a pass
-- has to exist for the right-hand side of this to ever be knowable.
create function sabotage_draft_private.turn_complete(
  p_match_id uuid, p_round smallint, p_active_user uuid
)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select sabotage_draft_private.has_picked(p_match_id, p_round, p_active_user)
     and (
       select count(*) from (
         select user_id from public.sabotage_draft_guesses
          where match_id = p_match_id and round_number = p_round and target_user_id = p_active_user
         union
         select user_id from public.sabotage_draft_passes
          where match_id = p_match_id and round_number = p_round and target_user_id = p_active_user
       ) acted
     ) = sabotage_draft_private.player_count(p_match_id) - 1;
$$;

-- The one batch resolution for a turn's guesses, run exactly once per turn,
-- either the moment turn_complete goes true or the moment the shared clock
-- expires. Every pending guess for this turn resolves here, in the order it
-- was made, against the pick as it stands at that instant -- so an earlier
-- guess's hit can change what a later pending guess is actually checked
-- against, the same cascading behavior a live-resolved guess always had,
-- just deferred to one moment instead of spread across however many
-- submit_guess calls arrived first. Finishes by handing the turn onward,
-- the same way the old guess-window-close transition used to.
create function sabotage_draft_private.resolve_turn(p_match_id uuid)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_board     public.sabotage_draft_matches;
  v_round     public.sabotage_draft_rounds;
  v_active    uuid;
  v_franchise text;
  v_pick      public.sabotage_draft_picks;
  v_guess     record;
  v_drawn     record;
  v_exact     boolean;
  v_kind      text;
  v_result    sabotage_draft.guess_result;
begin
  select * into v_board from public.sabotage_draft_matches where match_id = p_match_id;
  v_active := sabotage_draft_private.active_user(p_match_id, v_board.active_seat);
  select * into v_round from public.sabotage_draft_rounds
   where match_id = p_match_id and round_number = v_board.current_round;
  v_franchise := sabotage_draft_private.spin_franchise(p_match_id, v_board.current_round, v_active);

  for v_guess in
    select * from public.sabotage_draft_guesses
     where match_id = p_match_id and round_number = v_board.current_round
       and target_user_id = v_active and result is null
     order by id
  loop
    select * into v_pick from public.sabotage_draft_picks
     where match_id = p_match_id and round_number = v_board.current_round and user_id = v_active;
    v_exact := v_pick.player_id = v_guess.player_id and (v_guess.season is null or v_pick.season = v_guess.season);
    v_kind := case when v_guess.season is null then 'respin' else 'sabotage' end;

    if v_exact and not exists (
      select 1 from public.sabotage_draft_pick_hits
       where match_id = p_match_id and round_number = v_board.current_round
         and target_user_id = v_active and kind = v_kind
    ) then
      insert into public.sabotage_draft_pick_hits (match_id, round_number, target_user_id, kind, guesser_user_id)
      values (p_match_id, v_board.current_round, v_active, v_kind, v_guess.user_id);

      if v_kind = 'respin' then
        select * into v_drawn from sabotage_draft_private.random_pick(
          v_franchise, sabotage_draft_private.pool_categories(v_round.slot)
        );
        update public.sabotage_draft_picks
           set player_id = v_drawn.player_id, display_name = v_drawn.display_name,
               season = v_drawn.season, by_timeout = false
         where match_id = p_match_id and round_number = v_board.current_round and user_id = v_active;
        v_result := 'respun';
      else
        update public.sabotage_draft_picks
           set player_id = v_guess.replacement_player_id,
               display_name = (
                 select display_name from private.av_roster_players
                  where franchise_code = v_franchise
                    and player_id = v_guess.replacement_player_id
                    and season = v_guess.replacement_season
                    and slot_category = any(sabotage_draft_private.pool_categories(v_round.slot))
               ),
               season = v_guess.replacement_season, by_timeout = false
         where match_id = p_match_id and round_number = v_board.current_round and user_id = v_active;
        v_result := 'sabotaged';
      end if;
    else
      v_result := 'miss';
    end if;

    update public.sabotage_draft_guesses set result = v_result
     where match_id = p_match_id and round_number = v_board.current_round
       and target_user_id = v_active and user_id = v_guess.user_id;
  end loop;

  perform sabotage_draft_private.advance_turn(p_match_id);
end;
$$;

create or replace function sabotage_draft_private.advance_turn(p_match_id uuid)
returns void
language plpgsql security definer set search_path = '' as $$
declare v_round smallint; v_seat smallint; v_count smallint;
begin
  select current_round, active_seat into v_round, v_seat
    from public.sabotage_draft_matches where match_id = p_match_id;
  v_count := sabotage_draft_private.player_count(p_match_id);

  if v_round = 14 then
    update public.sabotage_draft_matches
       set turn_deadline = null, x_factor_open = true
     where match_id = p_match_id;
    return;
  end if;

  if v_seat < v_count - 1 then
    update public.sabotage_draft_matches
       set active_seat = v_seat + 1, turn_deadline = now() + interval '45 seconds'
     where match_id = p_match_id;
  else
    update public.sabotage_draft_matches
       set current_round = v_round + 1, active_seat = 0, turn_deadline = now() + interval '45 seconds'
     where match_id = p_match_id;
  end if;
end;
$$;

-- ------------------------------------------------------------------ picks --

-- Submitting no longer opens a second window -- there is only the one
-- shared clock, already open since the turn started -- so a successful pick
-- only needs to check whether it was the last action the turn was waiting on.
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
  if v_board.turn_deadline is null or v_board.turn_deadline <= now() then raise exception 'turn_closed' using errcode = 'P0001'; end if;
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

  if sabotage_draft_private.turn_complete(p_match_id, v_board.current_round, v_user) then
    perform sabotage_draft_private.resolve_turn(p_match_id);
  end if;

  return v_pick;
end;
$$;

-- The active seat is still the only one who could possibly be missing a
-- pick when the shared clock runs out. Once that's settled (or was never
-- missing), resolve_turn runs unconditionally: any pending guess resolves
-- against whatever pick now exists, and any seat that neither guessed nor
-- passed simply contributes nothing, the same legal default absence has
-- always had here.
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
  if v_board.turn_deadline is null or v_board.turn_deadline > now() then return false; end if;

  v_active := sabotage_draft_private.active_user(p_match_id, v_board.active_seat);

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

  perform sabotage_draft_private.resolve_turn(p_match_id);
  return true;
end;
$$;

create or replace function sabotage_draft_private.sweep()
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare r record;
begin
  for r in
    select sm.match_id
      from public.sabotage_draft_matches sm
      join public.matches mt on mt.id = sm.match_id
     where mt.status = 'playing'::public.match_status
       and sm.turn_deadline is not null
       and sm.turn_deadline < now() - interval '2 seconds'
  loop
    perform sabotage_draft_private.expire(r.match_id);
  end loop;
end;
$$;

-- ---------------------------------------------------------------- guesses --

-- Signature unchanged from 0062 -- only the body changes, from resolving on
-- the spot to recording PENDING and letting resolve_turn settle it later.
create or replace function sabotage_draft.submit_guess(
  p_match_id uuid, p_player_id text, p_season smallint default null,
  p_replacement_player_id text default null, p_replacement_season smallint default null
)
returns public.sabotage_draft_guesses
language plpgsql security definer set search_path = '' as $$
declare
  v_user uuid := auth.uid(); v_board public.sabotage_draft_matches; v_round public.sabotage_draft_rounds;
  v_active uuid; v_franchise text; v_guess public.sabotage_draft_guesses;
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
  if v_user = v_active then raise exception 'not_your_turn' using errcode = 'P0001'; end if;
  if v_board.turn_deadline is null or v_board.turn_deadline <= now() then raise exception 'turn_closed' using errcode = 'P0001'; end if;

  if exists (select 1 from public.sabotage_draft_guesses where match_id = p_match_id and round_number = v_board.current_round and target_user_id = v_active and user_id = v_user)
     or exists (select 1 from public.sabotage_draft_passes where match_id = p_match_id and round_number = v_board.current_round and target_user_id = v_active and user_id = v_user)
  then raise exception 'already_acted' using errcode = 'P0001'; end if;

  select * into v_round from public.sabotage_draft_rounds where match_id = p_match_id and round_number = v_board.current_round;
  v_franchise := sabotage_draft_private.spin_franchise(p_match_id, v_board.current_round, v_active);
  if not exists (
    select 1 from private.av_roster_players
     where franchise_code = v_franchise and player_id = p_player_id
       and slot_category = any(sabotage_draft_private.pool_categories(v_round.slot))
  ) then raise exception 'invalid_guess' using errcode = 'P0001'; end if;

  if p_season is not null and not exists (
    select 1 from private.av_roster_players
     where franchise_code = v_franchise and player_id = p_replacement_player_id and season = p_replacement_season
       and slot_category = any(sabotage_draft_private.pool_categories(v_round.slot))
  ) then raise exception 'invalid_replacement' using errcode = 'P0001'; end if;

  -- result is NULL: pending, resolved by resolve_turn once the turn's
  -- action set is complete or the clock runs out -- see the header.
  insert into public.sabotage_draft_guesses (match_id, round_number, user_id, target_user_id, player_id, season, replacement_player_id, replacement_season, result)
  values (p_match_id, v_board.current_round, v_user, v_active, p_player_id, p_season, p_replacement_player_id, p_replacement_season, null)
  returning * into v_guess;

  if sabotage_draft_private.turn_complete(p_match_id, v_board.current_round, v_active) then
    perform sabotage_draft_private.resolve_turn(p_match_id);
  end if;

  return v_guess;
end;
$$;

-- ------------------------------------------------------------------ pass --

create function sabotage_draft.submit_pass(p_match_id uuid)
returns public.sabotage_draft_passes
language plpgsql security definer set search_path = '' as $$
declare
  v_user uuid := auth.uid(); v_board public.sabotage_draft_matches; v_active uuid; v_pass public.sabotage_draft_passes;
begin
  if v_user is null then raise exception 'not_authenticated' using errcode = '42501'; end if;
  select sm.* into v_board from public.sabotage_draft_matches sm join public.matches mt on mt.id = sm.match_id
   where sm.match_id = p_match_id and mt.status = 'playing'::public.match_status for update of sm;
  if not found then raise exception 'match_not_playing' using errcode = 'P0001'; end if;
  if not exists (select 1 from public.sabotage_draft_players where match_id = p_match_id and user_id = v_user) then
    raise exception 'not_a_participant' using errcode = '42501'; end if;

  v_active := sabotage_draft_private.active_user(p_match_id, v_board.active_seat);
  if v_user = v_active then raise exception 'not_your_turn' using errcode = 'P0001'; end if;
  if v_board.turn_deadline is null or v_board.turn_deadline <= now() then raise exception 'turn_closed' using errcode = 'P0001'; end if;

  if exists (select 1 from public.sabotage_draft_guesses where match_id = p_match_id and round_number = v_board.current_round and target_user_id = v_active and user_id = v_user)
     or exists (select 1 from public.sabotage_draft_passes where match_id = p_match_id and round_number = v_board.current_round and target_user_id = v_active and user_id = v_user)
  then raise exception 'already_acted' using errcode = 'P0001'; end if;

  insert into public.sabotage_draft_passes (match_id, round_number, target_user_id, user_id)
  values (p_match_id, v_board.current_round, v_active, v_user)
  returning * into v_pass;

  if sabotage_draft_private.turn_complete(p_match_id, v_board.current_round, v_active) then
    perform sabotage_draft_private.resolve_turn(p_match_id);
  end if;

  return v_pass;
end;
$$;

-- -------------------------------------------------------------- x-factor --

-- Only the deadline-column names change from 0062's version -- the
-- turn-per-seat sequencing this gates into is otherwise untouched.
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

  if v_board.current_round <> 14 or not v_board.x_factor_open or v_board.turn_deadline is not null then
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
           turn_deadline = now() + interval '45 seconds'
     where match_id = p_match_id;
  else
    perform sabotage_draft_private.maybe_complete(p_match_id);
  end if;

  return v_decision;
end;
$$;

-- ------------------------------------------------------------------- resume --

-- Only the sabotage_draft branch changes -- a pause now shifts the one
-- shared turn_deadline forward by however long the pause lasted, in place
-- of the two deadline columns this replaces.
create or replace function public.resume_match(p_match_id uuid)
returns public.matches
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_user    uuid := auth.uid();
  v_match   public.matches;
  v_run     public.runs;
  v_lobby   public.lobbies;
  v_elapsed interval;
begin
  if v_user is null or (auth.jwt() ->> 'is_anonymous')::boolean is true then
    raise exception 'not_authenticated' using errcode = '42501';
  end if;

  select * into v_match from public.matches where id = p_match_id for update;
  if not found then raise exception 'match_not_found' using errcode = 'P0001'; end if;

  select * into v_run from public.runs where id = v_match.run_id;
  if v_run.lobby_id is null then raise exception 'no_host' using errcode = '42501'; end if;

  select * into v_lobby from public.lobbies where id = v_run.lobby_id for update;
  if v_lobby.host_id <> v_user then raise exception 'not_host' using errcode = '42501'; end if;
  if not exists (
    select 1 from public.lobby_members
     where lobby_id = v_lobby.id and user_id = v_user and left_at is null
  ) then raise exception 'not_a_member' using errcode = '42501'; end if;

  if v_match.status <> 'paused'::public.match_status then
    raise exception 'match_not_paused' using errcode = 'P0001';
  end if;

  v_elapsed := now() - v_match.paused_at;

  case v_match.game
    when 'auction_team_builder' then
      update public.auction_matches
         set turn_deadline = turn_deadline + v_elapsed,
             phase_deadline = phase_deadline + v_elapsed
       where match_id = p_match_id;
    when 'higher_or_lower' then
      update public.higher_or_lower_matches
         set phase_deadline = phase_deadline + v_elapsed
       where match_id = p_match_id;
    when 'sabotage_draft' then
      update public.sabotage_draft_matches
         set turn_deadline = turn_deadline + v_elapsed
       where match_id = p_match_id;
    else
      null;
  end case;

  update public.matches
     set status = 'playing'::public.match_status, paused_at = null
   where id = p_match_id
  returning * into v_match;

  return v_match;
end;
$$;

-- ---------------------------------------------------------------- privileges --

revoke all on function sabotage_draft_private.turn_complete(uuid, smallint, uuid) from public, anon, authenticated;
revoke all on function sabotage_draft_private.resolve_turn(uuid) from public, anon, authenticated;

revoke all on function sabotage_draft.submit_pass(uuid) from public, anon;
grant execute on function sabotage_draft.submit_pass(uuid) to authenticated;
