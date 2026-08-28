-- Tests for the fixed season baseline (migration 0076): every roster's
-- season is now played against a constant, not the table's own average.
--
-- The full end-to-end path (deal, draft, X-Factor, simulate_season writing
-- seventeen-game records and a resolved match) is already covered by
-- 0056's own suite and is unchanged by this migration beyond which number
-- win_probability's second argument is -- those assertions (every seated
-- player gets a standing, each is seventeen games, ranks respect record,
-- and so on) still have to hold and this migration doesn't restate them.
-- What's specific to 0076 is the baseline value itself and the shape of
-- the curve it feeds, both of which are plain, deterministic SQL.
begin;
select plan(4);

\ir support/harness.psql

select is(sabotage_draft_private.baseline_roster_strength(), 93,
  'the fixed baseline is 93 -- the average real NFL team''s best lineup at each of the game''s thirteen slots, 2006-2025');

-- An even matchup (roster_strength equal to the baseline) is a coin flip,
-- exactly -- the same identity the table-mean version relied on for a
-- roster exactly at its own table's average, now anchored to a constant
-- instead of a moving target.
select is(sabotage_draft_private.win_probability(93, 93), 0.5::double precision,
  'a roster exactly at the baseline has exactly even odds against it');

-- Above the baseline is favored, below is not -- the direction the whole
-- redesign depends on: a genuinely strong roster should look genuinely
-- strong regardless of what anyone else at the table drafted.
select ok(sabotage_draft_private.win_probability(118, 93) > 0.5,
  'a roster 25 AV above the baseline (one "noticeable edge", per the season''s own doc comment) is favored');
select ok(sabotage_draft_private.win_probability(68, 93) < 0.5,
  'a roster 25 AV below the baseline is an underdog');

select * from finish();
rollback;
