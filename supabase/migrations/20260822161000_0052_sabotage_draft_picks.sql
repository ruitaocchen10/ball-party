-- Sabotage draft: the hidden pick, its clock, and the auto-substitution a
-- missed deadline produces. Issue #39, the second half of the slice 0051
-- opened. Guessing (#40) still does not exist — this is only what gets a
-- pick made, hidden, and eventually locked in, with nothing yet reading it
-- back except its own owner.
--
-- TWO THINGS ARE LOAD-BEARING HERE.
--
-- The first is where a pick's identity lives. Unlike the auction's lot/answer
-- split or Higher or Lower's card/answer split — both of which hide a value
-- from *everyone* until a shared reveal — a sabotage draft pick has to stay
-- hidden from every player except the one who made it, indefinitely, until a
-- later ticket resolves it. That is a different shape of secret than this
-- codebase has built before, and 0034's higher_or_lower_calls is the actual
-- precedent for it: the hidden column (there, `direction`; here, `player_id`
-- and `season`) sits directly on the client-readable, Realtime-published
-- table, and RLS — not a second physical table — is what keeps it from a
-- viewer who is not its owner. Realtime evaluates a subscriber's row
-- visibility through the same RLS a REST select would, so a SELECT policy of
-- `user_id = auth.uid()` really does stop the payload at the wire, not just
-- at the query the app happens to write. 0034's own leak coverage already
-- rests on this; the leak test below asserts the same property for a pick.
--
-- Presence, though, is not the same secret in a more useful form — it is a
-- different fact ("has this seat picked yet") that every player is allowed to
-- know regardless of whose seat it is. That is `sabotage_draft_pick_statuses`,
-- a bare presence row alongside the pick, the same split 0034 makes between
-- `higher_or_lower_calls` and `higher_or_lower_call_statuses`.
--
-- The second is the timeout substitution. A player who has not picked when
-- the clock runs out gets a fresh random player and season from the round's
-- own pool — never the highest-AV option, on purpose, so stalling the clock
-- is never a way to guarantee a good pick. sabotage_draft_private.random_pick
-- is written as its own function, reusable rather than inlined, because the
-- design doc calls for this exact draw a second time: a successful
-- name-only guess (#40) triggers the same respin. Building it once now means
-- #40 calls it instead of reinventing it.

-- ------------------------------------------------------------------- clock --

alter table public.sabotage_draft_matches
  add column pick_deadline timestamptz;

-- No match dealt before this migration exists yet (0051 shipped in this same
-- change), so there is nothing to backfill — unlike 0033, which had to give
-- already-playing Higher or Lower matches a clock retroactively.

alter type sabotage_draft.round add attribute pick_deadline timestamptz;
alter type sabotage_draft.round add attribute server_now timestamptz;

create or replace function sabotage_draft_private.round_of(p_match_id uuid)
returns sabotage_draft.round
language sql
stable
security definer
set search_path = ''
as $$
  select (m.match_id, m.round_count, m.current_round, r.slot, r.franchise_code,
          m.pick_deadline, now())::sabotage_draft.round
    from public.sabotage_draft_matches m
    join public.sabotage_draft_rounds r
      on r.match_id = m.match_id and r.round_number = m.current_round
   where m.match_id = p_match_id;
$$;

-- Redealt to open round one's pick window. The rest of the dealer is
-- unchanged from 0051; only the final insert gains a deadline.
--
-- Forty-five seconds is a starting number, the same spirit as 0032's band
-- schedule and the auction's turn clock: a guess at what searching a team's
-- history for one slot ought to take, to be tuned against real playtests
-- rather than argued about here.
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

    select r.franchise_code into v_franchise
      from private.av_roster_players r
     where r.slot_category = any(sabotage_draft_private.pool_categories(v_slot))
     group by r.franchise_code
     order by random()
     limit 1;

    if not found then
      raise exception 'pool_exhausted' using errcode = 'P0001';
    end if;

    insert into public.sabotage_draft_rounds (match_id, round_number, slot, franchise_code)
    values (p_match_id, v_i, v_slot, v_franchise);
  end loop;

  insert into public.sabotage_draft_matches (match_id, round_count, current_round, pick_deadline)
  values (p_match_id, 14, 1, now() + interval '45 seconds');

  insert into sabotage_draft_private.boards (match_id, seed) values (p_match_id, v_seed);
end;
$$;

-- -------------------------------------------------------------------- picks --

-- The secret. See the header for why it is a column here rather than a
-- physically separate table.
create table public.sabotage_draft_picks (
  match_id     uuid     not null references public.matches (id) on delete cascade,
  round_number smallint not null,
  user_id      uuid     not null,
  player_id    text     not null,
  display_name text     not null,
  season       smallint not null,
  -- True when the pick timer, not the player, chose this. Reserved for #40's
  -- disconnect story and for a "you were sniped by the clock" UI cue; not
  -- read by anything in this migration beyond being recorded honestly.
  by_timeout   boolean  not null default false,
  created_at   timestamptz not null default now(),

  primary key (match_id, round_number, user_id),
  foreign key (match_id, user_id)
    references public.sabotage_draft_players (match_id, user_id) on delete cascade,
  foreign key (match_id, round_number)
    references public.sabotage_draft_rounds (match_id, round_number)
);

-- Presence. Intentionally not a projection of picks — see the header.
create table public.sabotage_draft_pick_statuses (
  match_id     uuid     not null references public.matches (id) on delete cascade,
  round_number smallint not null,
  user_id      uuid     not null,
  created_at   timestamptz not null default now(),

  primary key (match_id, round_number, user_id),
  foreign key (match_id, user_id)
    references public.sabotage_draft_players (match_id, user_id) on delete cascade
);

create function sabotage_draft_private.has_picked(
  p_match_id uuid,
  p_round smallint,
  p_user_id uuid
)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1 from public.sabotage_draft_pick_statuses
     where match_id = p_match_id and round_number = p_round and user_id = p_user_id
  );
$$;

-- Whether every seated player has a pick in for this round — the moment
-- picks lock, per the design doc, and the signal this file uses to close the
-- window the instant the last pick lands rather than waiting on the clock.
create function sabotage_draft_private.all_picked(p_match_id uuid, p_round smallint)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select (select count(*) from public.sabotage_draft_players where match_id = p_match_id)
       = (select count(*) from public.sabotage_draft_pick_statuses
           where match_id = p_match_id and round_number = p_round);
$$;

-- A fresh random player and season from a franchise's history at one or more
-- pool categories. Not STABLE: a caching-safe "same arguments, same answer"
-- promise is exactly what this must not make, since the whole point is a
-- fresh draw each call. Used by the timeout path below, and reserved for
-- #40's name-only-guess respin, which the design doc calls "the same
-- random-respin outcome."
create function sabotage_draft_private.random_pick(
  p_franchise_code text,
  p_categories text[],
  out player_id text,
  out display_name text,
  out season smallint
)
language sql
security definer
set search_path = ''
as $$
  select r.player_id, r.display_name, r.season
    from private.av_roster_players r
   where r.franchise_code = p_franchise_code
     and r.slot_category = any(p_categories)
   order by random()
   limit 1;
$$;

-- The write. One pick per player per round, validated against the round's own
-- franchise and eligible categories rather than trusted from the client.
create function sabotage_draft.submit_pick(
  p_match_id uuid,
  p_player_id text,
  p_season smallint
)
returns public.sabotage_draft_picks
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_user  uuid := auth.uid();
  v_board public.sabotage_draft_matches;
  v_round public.sabotage_draft_rounds;
  v_pick  public.sabotage_draft_picks;
  v_name  text;
begin
  if v_user is null then
    raise exception 'not_authenticated' using errcode = '42501';
  end if;

  -- One match-row lock serializes the deadline check and the duplicate-pick
  -- check against a second submission arriving a moment later, the same
  -- reasoning 0034's higher_or_lower.call gives for locking its board row.
  select sm.* into v_board
    from public.sabotage_draft_matches sm
    join public.matches mt on mt.id = sm.match_id
   where sm.match_id = p_match_id
     and mt.status = 'playing'::public.match_status
   for update of sm;
  if not found then
    raise exception 'match_not_playing' using errcode = 'P0001';
  end if;

  if not exists (
    select 1 from public.sabotage_draft_players
     where match_id = p_match_id and user_id = v_user
  ) then
    raise exception 'not_a_participant' using errcode = '42501';
  end if;

  if v_board.pick_deadline is null or v_board.pick_deadline <= now() then
    raise exception 'pick_window_closed' using errcode = 'P0001';
  end if;

  if sabotage_draft_private.has_picked(p_match_id, v_board.current_round, v_user) then
    raise exception 'already_picked' using errcode = 'P0001';
  end if;

  select * into v_round from public.sabotage_draft_rounds
   where match_id = p_match_id and round_number = v_board.current_round;

  -- The pick has to be a real player who actually played this franchise, this
  -- year, at a category this round's slot allows — sourced from #38's pool
  -- rather than trusted from the arguments. display_name is copied from
  -- there too, so the picker's own read of their pick never depends on a
  -- second, possibly-stale source.
  select display_name into v_name
    from private.av_roster_players
   where franchise_code = v_round.franchise_code
     and player_id = p_player_id
     and season = p_season
     and slot_category = any(sabotage_draft_private.pool_categories(v_round.slot));
  if not found then
    raise exception 'invalid_pick' using errcode = 'P0001';
  end if;

  insert into public.sabotage_draft_picks (
    match_id, round_number, user_id, player_id, display_name, season, by_timeout
  )
  values (p_match_id, v_board.current_round, v_user, p_player_id, v_name, p_season, false)
  returning * into v_pick;

  insert into public.sabotage_draft_pick_statuses (match_id, round_number, user_id)
  values (p_match_id, v_board.current_round, v_user);

  -- Picks lock simultaneously: the moment the last seat's pick lands, the
  -- window closes right here rather than waiting out a clock nobody needs
  -- anymore.
  if sabotage_draft_private.all_picked(p_match_id, v_board.current_round) then
    update public.sabotage_draft_matches set pick_deadline = null where match_id = p_match_id;
  end if;

  return v_pick;
end;
$$;

-- ------------------------------------------------------------------- timer --

-- Substitutes a fresh random pick for every seat still missing one once the
-- deadline has passed, then closes the window. Idempotent: called again
-- before the next round opens a new deadline, it finds pick_deadline already
-- null and does nothing.
create function sabotage_draft_private.expire(p_match_id uuid)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_board  public.sabotage_draft_matches;
  v_round  public.sabotage_draft_rounds;
  v_missing record;
  v_drawn   record;
begin
  select sm.* into v_board
    from public.sabotage_draft_matches sm
    join public.matches mt on mt.id = sm.match_id
   where sm.match_id = p_match_id
     and mt.status = 'playing'::public.match_status
   for update of sm;

  if not found or v_board.pick_deadline is null or v_board.pick_deadline > now() then
    return false;
  end if;

  select * into v_round from public.sabotage_draft_rounds
   where match_id = p_match_id and round_number = v_board.current_round;

  for v_missing in
    select sp.user_id from public.sabotage_draft_players sp
     where sp.match_id = p_match_id
       and not sabotage_draft_private.has_picked(p_match_id, v_board.current_round, sp.user_id)
  loop
    select * into v_drawn from sabotage_draft_private.random_pick(
      v_round.franchise_code, sabotage_draft_private.pool_categories(v_round.slot)
    );
    if not found then
      raise exception 'pool_exhausted' using errcode = 'P0001';
    end if;

    insert into public.sabotage_draft_picks (
      match_id, round_number, user_id, player_id, display_name, season, by_timeout
    )
    values (
      p_match_id, v_board.current_round, v_missing.user_id,
      v_drawn.player_id, v_drawn.display_name, v_drawn.season, true
    );

    insert into public.sabotage_draft_pick_statuses (match_id, round_number, user_id)
    values (p_match_id, v_board.current_round, v_missing.user_id);
  end loop;

  update public.sabotage_draft_matches set pick_deadline = null where match_id = p_match_id;
  return true;
end;
$$;

-- A client clock is the fast path; any participant may ask for expiry and it
-- does not matter who gets there first, since expire re-checks its own
-- deadline while holding the match row lock.
create function sabotage_draft.tick(p_match_id uuid)
returns sabotage_draft.round
language plpgsql
security definer
set search_path = ''
as $$
declare v_user uuid := auth.uid();
begin
  if v_user is null then
    raise exception 'not_authenticated' using errcode = '42501';
  end if;
  if not exists (
    select 1 from public.sabotage_draft_players
     where match_id = p_match_id and user_id = v_user
  ) then
    raise exception 'not_a_participant' using errcode = '42501';
  end if;
  perform sabotage_draft_private.expire(p_match_id);
  return sabotage_draft_private.round_of(p_match_id);
end;
$$;

-- The one-minute-scale backstop for a match nobody has open — the same shape
-- as the auction's and Higher or Lower's own sweeps.
create function sabotage_draft_private.sweep()
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
       and sm.pick_deadline is not null
       and sm.pick_deadline < now() - interval '2 seconds'
  loop
    perform sabotage_draft_private.expire(r.match_id);
  end loop;
end;
$$;

select cron.schedule(
  'sabotage-draft-sweep',
  '30 seconds',
  $$ select sabotage_draft_private.sweep() $$
);

-- ---------------------------------------------------------------------- RLS --

alter table public.sabotage_draft_picks         enable row level security;
alter table public.sabotage_draft_pick_statuses enable row level security;

-- The load-bearing policy: a pick's identity is visible to its own owner and
-- nobody else. No "or has picked too" clause the way 0034's calls policy has
-- one — unlike a simultaneous prediction, a sabotage draft pick stays a
-- secret from every other player regardless of what they themselves have
-- done, until a later ticket resolves it.
create policy sabotage_draft_picks_select_own on public.sabotage_draft_picks
  for select to authenticated using (user_id = auth.uid());

create policy sabotage_draft_pick_statuses_select_member on public.sabotage_draft_pick_statuses
  for select to authenticated using (private.is_match_member(match_id));

grant select on public.sabotage_draft_picks         to authenticated;
grant select on public.sabotage_draft_pick_statuses to authenticated;

-- ----------------------------------------------------------------- realtime --
-- Both tables replicate. sabotage_draft_picks is safe to replicate precisely
-- because the RLS policy above is what Realtime evaluates per subscriber —
-- the same reliance 0034's higher_or_lower_calls already has, and the leak
-- test in the paired test file for this migration asserts it holds here too.

alter publication supabase_realtime add table public.sabotage_draft_picks;
alter publication supabase_realtime add table public.sabotage_draft_pick_statuses;

-- ---------------------------------------------------------------- privileges --

revoke all on function sabotage_draft_private.has_picked(uuid, smallint, uuid) from public, anon, authenticated;
revoke all on function sabotage_draft_private.all_picked(uuid, smallint)       from public, anon, authenticated;
revoke all on function sabotage_draft_private.random_pick(text, text[])       from public, anon, authenticated;
revoke all on function sabotage_draft_private.expire(uuid)                    from public, anon, authenticated;
revoke all on function sabotage_draft_private.sweep()                        from public, anon, authenticated;

revoke all on function sabotage_draft.submit_pick(uuid, text, smallint) from public, anon;
revoke all on function sabotage_draft.tick(uuid)                        from public, anon;

grant execute on function sabotage_draft.submit_pick(uuid, text, smallint) to authenticated;
grant execute on function sabotage_draft.tick(uuid)                        to authenticated;
