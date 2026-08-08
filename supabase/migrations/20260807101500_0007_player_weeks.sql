-- The auction's lot pool: one row per NFL player-week, 2010-2025.
--
-- Rows are loaded by a later data migration; see scripts/player_pool/.
--
-- WHY `private`: the fantasy points on a lot must be unreadable by the client
-- until the lot resolves. PostgREST only exposes configured schemas, so a table
-- in `private` has no REST endpoint at all — the same reasoning that moved the
-- RLS helpers here in 0004. That is an absence of endpoint rather than a policy
-- that could later be widened by accident, which is why no RLS policies are
-- written below: nothing reachable can select from this table.
--
-- The auction reads it from inside a `security definer` function at match
-- start, copying only the card-visible fields onto its own lot rows. `points`
-- travels separately and stays hidden until the reveal.

create table private.player_weeks (
  -- Card-visible. Safe to copy onto a client-readable lot row.
  player_id    text         not null,
  display_name text         not null,
  position     text         not null check (position in ('QB','RB','WR','TE')),
  -- Lower bound only. The era range is the build script's business, and a
  -- newly completed season arrives as a new migration inserting its rows —
  -- an upper bound here would mean every such migration also had to alter a
  -- constraint. This catches a corrupt load, not a policy.
  season       smallint     not null check (season >= 2010),
  week         smallint     not null check (week between 1 and 18),
  team         text         not null,
  opponent     text         not null,

  -- Hidden. Never projected onto a lot before it resolves.
  points       numeric(5,1) not null,

  -- Player-season properties, denormalised onto every week of that season.
  -- Two tables would be more normalised and would make dealing a board a join;
  -- at ~40k frozen rows the redundancy costs nothing and cannot drift, because
  -- nothing ever updates.
  pos_rank     smallint     not null check (pos_rank > 0),
  tier         text         not null check (tier in ('star','solid','deep')),

  primary key (player_id, season, week)
);

-- Dealing a board is a query by position and tier against the quota.
create index player_weeks_by_position_tier on private.player_weeks (position, tier);

-- Belt and braces, in the same spirit as the schema choice above. The table is
-- already unreachable from PostgREST, but neither of these should be the only
-- thing standing between a player and the answers: no role holds table
-- privileges, and RLS with no policy denies everything anyway. A definer
-- function reads this, and the table owner bypasses RLS, so the auction's read
-- path is unaffected.
revoke all on table private.player_weeks from public, anon, authenticated;
alter table private.player_weeks enable row level security;
