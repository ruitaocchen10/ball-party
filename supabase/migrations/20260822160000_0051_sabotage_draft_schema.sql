-- Sabotage draft: its schema pair, the fourteen-round team spin, and the
-- entry point that deals it. See docs/games/sabotage_draft.md and issue #39.
--
-- THIS SLICE IS THE SPIN AND NOTHING ELSE. A dealt match holds all fourteen
-- rounds' team spins, each with its fixed (or, for round 14, widened) slot,
-- and a pointer at whichever round is current. The pick itself — the hidden
-- half of a round — is 0052. Guessing (#40) is not built here at all.
--
-- Follows the pattern 0029 (auction) and 0032 (Higher or Lower) already
-- established, exactly:
--
--   sabotage_draft          the write API a client may call. Exposed via
--                           PostgREST, so it holds nothing not meant to be
--                           reachable.
--   sabotage_draft_private  the rules engine. Not in the exposed schema list
--                           and no usage granted to anon or authenticated, so
--                           it is unreachable rather than merely unrouted.
--
-- The names are `matches.game` verbatim. Exposing the public one also takes an
-- entry in `[api] schemas` in config.toml AND the hosted project's
-- exposed-schema dashboard setting, which is state no migration can carry —
-- see supabase/README.md, updated alongside this file.
--
-- Whole board dealt up front, in one transaction, the same call 0010 (auction
-- lots) and 0032 (the ladder) both already made: a half-dealt match is a
-- broken one. All fourteen team spins land in sabotage_draft_rounds at deal
-- time — a franchise is not excluded from a later round for having already
-- come up, so nothing here tracks one. Nothing about the team spin is secret
-- ("visible to the whole table" per the design doc), so there is no reason to
-- hide round 9's spin from a table still on round 1.
--
-- ROUND CAPACITY, NAMED HONESTLY: the design doc calls for a two-to-six table.
-- The platform's own lobby cap is four everywhere it is enforced today
-- (0005's join check, 0009's start_run count check, match_players.placement's
-- 1..4 check) — shared code every game runs through, not this game's to
-- widen on its own. This ticket deals against that existing four-player
-- ceiling rather than raising it; getting to six is a platform-wide change
-- for a follow-up ticket, not smuggled in here.

-- ------------------------------------------------------------------ the name --
-- `matches.game`'s check constraint is the platform's registry of games that
-- exist at all (0003). auction_team_builder and higher_or_lower were named
-- there from the start; sabotage_draft was not, so it needs adding rather
-- than inheriting a slot nobody reserved for it.
alter table public.matches drop constraint matches_game_check;
alter table public.matches add constraint matches_game_check check (game in (
  'auction_team_builder',
  'cards_against_humanity',
  'higher_or_lower',
  'wavelength_2v2',
  'sabotage_draft'
));

-- ------------------------------------------------------------------ schemas --

create schema if not exists sabotage_draft;
create schema if not exists sabotage_draft_private;

revoke all on schema sabotage_draft_private from public, anon, authenticated;

revoke all on schema sabotage_draft from public;
grant usage on schema sabotage_draft to anon, authenticated, service_role;

-- ------------------------------------------------------------------- tables --

-- The match's round pointer. Everything else about format is fixed by the
-- game's own rules rather than dealt per-match, so unlike the auction's
-- roster preset or Higher or Lower's question count there is no format to
-- snapshot here beyond the round count itself — recorded anyway, in the same
-- spirit those two record theirs, so a constant that later becomes
-- configurable does not need a column added retroactively to every finished
-- match.
create table public.sabotage_draft_matches (
  match_id      uuid     primary key references public.matches (id) on delete cascade,
  round_count   smallint not null default 14 check (round_count = 14),
  current_round smallint not null default 1 check (current_round between 1 and round_count)
);

-- The team spin. One row per round, all fourteen dealt at once — see the
-- header. `slot` is the roster slot this round fills; rounds 1-13 are fixed,
-- in the order the design doc lists (QB, RB1, RB2, WR1-3, TE, OL, DL, LB, CB,
-- S, Special Teams), and round 14 — the X-Factor — has no single fixed slot
-- at all: its eligible pick set is any of QB/RB/WR/TE, decided by the picker
-- at pick time, not by the spin. `franchise_code` is Pro Football Reference's
-- own stable code (see docs/games/sabotage_draft_data_scoping.md §2) —
-- unifying relocations and renames under one code is exactly what lets a
-- single column mean "this franchise, any year."
create table public.sabotage_draft_rounds (
  match_id       uuid     not null references public.matches (id) on delete cascade,
  round_number   smallint not null check (round_number between 1 and 14),
  slot           text     not null check (slot in (
                   'QB', 'RB1', 'RB2', 'WR1', 'WR2', 'WR3', 'TE',
                   'OL', 'DL', 'LB', 'CB', 'S', 'ST', 'X_FACTOR'
                 )),
  franchise_code text     not null,

  primary key (match_id, round_number)
);

-- Who is playing. Seats copied from run_participants rather than shuffled
-- again, for the same reason 0032 gives: the platform froze the order at run
-- start, and a game that reshuffles it is inventing a second answer to a
-- question already settled.
create table public.sabotage_draft_players (
  match_id uuid     not null references public.matches (id) on delete cascade,
  user_id  uuid     not null references public.profiles (id),
  seat     smallint not null,

  primary key (match_id, user_id),
  unique (match_id, seat)
);

-- The seed a board was dealt from. Same treatment as
-- higher_or_lower_private.boards: no endpoint, no privileges, RLS on with no
-- policies, never in a publication. The team spin is public, but the dealer
-- that produces it — the franchise universe, the slot order — lives in this
-- repository, so a seed handed to a client would let them precompute every
-- future round's spin ahead of the table seeing it.
create table sabotage_draft_private.boards (
  match_id uuid             primary key references public.matches (id) on delete cascade,
  seed     double precision not null,
  dealt_at timestamptz      not null default now()
);

revoke all on table sabotage_draft_private.boards from public, anon, authenticated;
alter table sabotage_draft_private.boards enable row level security;

-- ------------------------------------------------------------- the pool map --

-- A round's fixed slot to the pool's slot_category (private.av_roster_players
-- in 0049/0050): a straight rename for most, RB1/RB2 both onto 'RB' and
-- WR1/2/3 all onto 'WR' since the pool doesn't distinguish roster order, and
-- the X-Factor onto all four skill categories at once, since its eligible
-- pick set is every one of them rather than a single fixed slot.
create function sabotage_draft_private.pool_categories(p_slot text)
returns text[]
language plpgsql
immutable
set search_path = ''
as $$
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
$$;

-- --------------------------------------------------------------- the deal --

-- Draws all fourteen team spins in one transaction — see the header for why.
--
-- The seed is an argument so tests can pin a board, exactly the reason
-- higher_or_lower_private.deal_board and auction_private.deal_board both take
-- one. Deliberately NOT an argument of the public entry point (sabotage_draft.
-- start, below): a client that chose the seed could precompute every round's
-- spin against the public franchise/pool data before the table saw the first
-- one.
create function sabotage_draft_private.deal_board(
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
  -- Rounds 1-13's fixed order, verbatim from the design doc. Round 14 is
  -- appended below rather than folded into this array, since its slot is not
  -- one of these fourteen fixed names.
  v_slots constant text[] := array[
    'QB', 'RB1', 'RB2', 'WR1', 'WR2', 'WR3', 'TE',
    'OL', 'DL', 'LB', 'CB', 'S', 'ST'
  ];
begin
  -- Parallelism off for the duration, the same reason both existing dealers
  -- turn it off: a parallel worker has its own PRNG state, and the seed would
  -- stop meaning anything.
  perform setseed(v_seed);
  set local max_parallel_workers_per_gather = 0;

  insert into public.sabotage_draft_players (match_id, user_id, seat)
  select p_match_id, rp.user_id, rp.seat
    from public.run_participants rp
    join public.matches m on m.run_id = rp.run_id
   where m.id = p_match_id;

  select count(*) into v_n from public.sabotage_draft_players where match_id = p_match_id;

  -- The platform already refuses a lobby outside 2-4 (0009). This is the
  -- game's own floor, which belongs here the way every other dealer's does:
  -- the platform must not learn what any particular game needs.
  if v_n < 2 then
    raise exception 'too_few_players' using errcode = 'P0001';
  end if;

  for v_i in 1 .. 14 loop
    v_slot := case when v_i <= 13 then v_slots[v_i] else 'X_FACTOR' end;

    -- A franchise drawn at random from every code that has players at this
    -- round's category (or categories, for the X-Factor) — no exclusion set,
    -- so the same franchise can come up again in a later round. The build
    -- guard in scripts/av_roster_pool/build_pool.py already guarantees every
    -- known franchise has every category populated, so in practice this never
    -- narrows the draw; the filter stays because a query that assumes its own
    -- data unconditionally is the wrong place to first find out it's wrong.
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

  insert into public.sabotage_draft_matches (match_id, round_count, current_round)
  values (p_match_id, 14, 1);

  insert into sabotage_draft_private.boards (match_id, seed) values (p_match_id, v_seed);
end;
$$;

-- --------------------------------------------------------- the entry point --

-- What a client is told about the match. A projection, not the table: adding
-- a column to sabotage_draft_matches must never be silently also a decision
-- to publish it. The pick clock joins this in 0052.
create type sabotage_draft.round as (
  match_id       uuid,
  round_count    smallint,
  current_round  smallint,
  slot           text,
  franchise_code text
);

create function sabotage_draft_private.round_of(p_match_id uuid)
returns sabotage_draft.round
language sql
stable
security definer
set search_path = ''
as $$
  select (m.match_id, m.round_count, m.current_round, r.slot, r.franchise_code)::sabotage_draft.round
    from public.sabotage_draft_matches m
    join public.sabotage_draft_rounds r
      on r.match_id = m.match_id and r.round_number = m.current_round
   where m.match_id = p_match_id;
$$;

-- The reconnect contract: any match member can ask what round the table is
-- on and what it spun, whether or not they have picked yet.
create function sabotage_draft.state(p_match_id uuid)
returns sabotage_draft.round
language plpgsql
security definer
set search_path = ''
as $$
begin
  if not private.is_match_member(p_match_id) then
    raise exception 'not_a_participant' using errcode = '42501';
  end if;
  return sabotage_draft_private.round_of(p_match_id);
end;
$$;

-- Takes no seed, on purpose — see the dealer.
create function sabotage_draft.start(p_match_id uuid)
returns sabotage_draft.round
language plpgsql
security definer
set search_path = ''
as $$
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

  perform sabotage_draft_private.deal_board(p_match_id, null);

  update public.matches
     set status = 'playing'::public.match_status,
         started_at = now()
   where id = p_match_id;

  return sabotage_draft_private.round_of(p_match_id);
end;
$$;

-- ---------------------------------------------------------------------- RLS --

alter table public.sabotage_draft_matches enable row level security;
alter table public.sabotage_draft_rounds  enable row level security;
alter table public.sabotage_draft_players enable row level security;

-- private.is_match_member is the platform's membership helper (0010), reached
-- from a policy rather than from this game's code — the module rule the
-- architecture doc describes runs the other way: a game may not reach into
-- lobbies, and this does not, it asks a question the platform answers.
create policy sabotage_draft_matches_select_member on public.sabotage_draft_matches
  for select to authenticated using (private.is_match_member(match_id));

create policy sabotage_draft_rounds_select_member on public.sabotage_draft_rounds
  for select to authenticated using (private.is_match_member(match_id));

create policy sabotage_draft_players_select_member on public.sabotage_draft_players
  for select to authenticated using (private.is_match_member(match_id));

-- No INSERT/UPDATE/DELETE policies anywhere, consistent with every table
-- since 0003. Every write goes through a definer function, owned by postgres,
-- which bypasses both the grant and the policy.

grant select on public.sabotage_draft_matches to authenticated;
grant select on public.sabotage_draft_rounds  to authenticated;
grant select on public.sabotage_draft_players to authenticated;

-- ----------------------------------------------------------------- realtime --
-- The three client-readable tables, and neither private one. RLS applies to
-- replication, so these fan out only to players in the match — and there is
-- nothing on any of these three rows a non-member or a future opponent should
-- not see, since the team spin is public by design.

alter publication supabase_realtime add table public.sabotage_draft_matches;
alter publication supabase_realtime add table public.sabotage_draft_rounds;
alter publication supabase_realtime add table public.sabotage_draft_players;

-- ---------------------------------------------------------------- privileges --
-- CREATE FUNCTION grants EXECUTE to PUBLIC by default. Take it back, then
-- hand out only what a signed-in player is allowed to ask for.

revoke all on function sabotage_draft_private.pool_categories(text)          from public, anon, authenticated;
revoke all on function sabotage_draft_private.round_of(uuid)                 from public, anon, authenticated;
revoke all on function sabotage_draft_private.deal_board(uuid, double precision)
  from public, anon, authenticated;

revoke all on function sabotage_draft.state(uuid) from public, anon;
revoke all on function sabotage_draft.start(uuid) from public, anon;

grant execute on function sabotage_draft.state(uuid) to authenticated;
grant execute on function sabotage_draft.start(uuid) to authenticated;
