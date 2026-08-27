-- Portrait shots for sabotage draft's roster pool.
--
-- Kept in its own table rather than a column on `private.av_roster_players`,
-- the same call 0013 made for the auction's own player_weeks: a headshot is
-- a fact about a player, not about a player-franchise-season, and the pool
-- carries one row per (franchise, season, slot) a player appears at.
--
-- WHY `private`, when the images themselves are public: the pool stays
-- private so a client cannot enumerate what a round might deal — a public
-- headshot table would hand over the same ~7,800-name list by another
-- route, the same reasoning 0013 gives for the auction's identical table.
--
-- WHY keyed on the PFR id rather than the GSIS id 0013's `player_headshots`
-- uses: `av_roster_players.player_id` already is the PFR id (0049/0050 —
-- both of this pool's sources key identity that way), and nflverse's own
-- player release carries a `pfr_id` column directly, so joining this pool to
-- a portrait needs no GSIS crosswalk. That also means this table cannot
-- share 0013's `private.player_headshots` — the id spaces are different
-- player-id schemes that happen to collide in shape (both are text), not the
-- same identity.
create table private.av_player_headshots (
  player_id    text primary key,
  headshot_url text not null
);

-- Belt and braces, same as every other `private` table: no role holds table
-- privileges, and RLS with no policy denies everything anyway. A definer
-- function reads this, and the table owner bypasses RLS, so the game's own
-- read path is unaffected.
revoke all on table private.av_player_headshots from public, anon, authenticated;
alter table private.av_player_headshots enable row level security;
