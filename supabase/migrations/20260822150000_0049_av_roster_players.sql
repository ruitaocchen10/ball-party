-- Sabotage draft's roster pool: one row per player-season, per franchise,
-- per roster-slot category, 2006-2025 (2006-2019 from nflverse, 2020-2025
-- from a cached Pro Football Reference scrape — see scripts/av_roster_pool/).
--
-- Rows are loaded by a later data migration; see scripts/av_roster_pool/.
--
-- Lives in the same shared `private` schema as `private.player_weeks`
-- rather than in a sabotage-draft-specific schema: this is a content pool,
-- the same kind of thing the auction's player pool already is, not game
-- state. Where sabotage draft's own `sabotage_draft`/`sabotage_draft_private`
-- schema pair lives is a separate decision for whichever ticket first deals
-- a round from this table.
--
-- WHY `private`: no other game reads Approximate Value, and there is no
-- reason for it to be client-readable before a round resolves. A table in
-- `private` has no REST endpoint at all — the same reasoning as
-- `player_weeks` in 0007. Game logic reads this from inside a
-- `security definer` function and copies only what a round's UI needs.
--
-- WHY `slot_category` is part of the primary key rather than just
-- (franchise_code, season, player_id): it never needs to be, in practice —
-- the build's own position-folding rule resolves a multi-position player to
-- exactly one category per team-season — but the key is written this wide
-- so a build that ever needs to loosen that rule doesn't also need a
-- primary-key migration to go with it.
create table private.av_roster_players (
  franchise_code text     not null,
  -- Lower bound only, mirroring player_weeks's own season check: the era
  -- range is the build script's business, and extending it later is a new
  -- migration inserting more rows, not an edit to this constraint.
  season         smallint not null check (season >= 2006),
  player_id      text     not null,
  display_name   text     not null,
  slot_category  text     not null
                 check (slot_category in ('QB','RB','WR','TE','OL','DL','LB','CB','S','ST')),
  -- Real Approximate Value seasons can be negative (confirmed in the
  -- source: a handful of quarterbacks and kickers with a single-digit
  -- negative-AV season) — this is PFR's own metric doing what it does, not
  -- a data error, so the column allows it.
  av             smallint not null,

  primary key (franchise_code, season, player_id, slot_category)
);

-- Dealing a round is "this franchise, this slot, any year" — a query by
-- franchise and slot against the whole era range.
create index av_roster_players_by_franchise_slot on private.av_roster_players (franchise_code, slot_category);

-- Belt and braces, same as player_weeks in 0007: the table is already
-- unreachable from PostgREST, but neither of these should be the only thing
-- standing between a player and an unrevealed pick. No role holds table
-- privileges, and RLS with no policy denies everything anyway. A definer
-- function reads this, and the table owner bypasses RLS, so the game's own
-- read path is unaffected.
revoke all on table private.av_roster_players from public, anon, authenticated;
alter table private.av_roster_players enable row level security;
