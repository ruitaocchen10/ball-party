"""Tests for the roster-pool transform.

The transform is the only seam here: raw rows from both sources in, finished
`private.av_roster_players` rows out. Fetching, artifact writing and database
loading sit outside it and are covered by the build-time guards instead.

Run with: python3 -m unittest discover scripts/av_roster_pool
"""

import unittest

import build_pool
from transform import transform


def nflverse_row(**over):
    """One nflverse `rosters.csv` row, in its own column names."""
    row = {
        "season": "2015",
        "team": "NYG",
        "playerid": "TestPl00",
        "full_name": "Test Player",
        "name": "T.Player",
        "side": "O",
        "category": "QB",
        "position": "QB",
        "games": "10",
        "starts": "8",
        "years": "3",
        "av": "5",
    }
    row.update({k: str(v) for k, v in over.items()})
    return row


def pfr_line(code="kan", season=2023, player_id="TestPl00", name="Test Player",
             pos="QB", av="5"):
    return f"{code}|{season}|{player_id}|{name}|{pos}|{av}"


class PositionFolding(unittest.TestCase):
    """Every era's position vocabulary folds onto the ten slot categories."""

    def test_1970s_style_side_encoded_string_folds(self):
        rows = transform([nflverse_row(position="LCB")], [])
        self.assertEqual(rows[0].slot_category, "CB")

        rows = transform([nflverse_row(position="SS")], [])
        self.assertEqual(rows[0].slot_category, "S")

        rows = transform([nflverse_row(position="LOLB")], [])
        self.assertEqual(rows[0].slot_category, "LB")

    def test_2020s_style_generic_string_folds_to_the_same_category(self):
        side_encoded = transform([nflverse_row(position="RCB")], [])[0]
        generic = transform([nflverse_row(position="CB")], [])[0]
        self.assertEqual(side_encoded.slot_category, generic.slot_category)

    def test_multi_position_string_resolves_to_one_category(self):
        rows = transform([], [pfr_line(pos="RG/LG")])
        self.assertEqual(len(rows), 1)
        self.assertEqual(rows[0].slot_category, "OL")

    def test_multi_position_string_first_listed_governs(self):
        # T-G: the 2020-2025 scrape's hyphen-separated form, not just the
        # modern slash. First-listed (T -> OL) wins either way.
        rows = transform([], [pfr_line(pos="T-G")])
        self.assertEqual(rows[0].slot_category, "OL")

        rows = transform([], [pfr_line(pos="TE/QB")])
        self.assertEqual(rows[0].slot_category, "TE")

    def test_generic_db_is_excluded_not_guessed(self):
        # PFR's own generic secondary tag carries no side information at
        # all — there is nothing here to fold onto CB or S.
        rows = transform([nflverse_row(position="DB")], [])
        self.assertEqual(rows, [])

    def test_unfoldable_position_is_excluded(self):
        rows = transform([nflverse_row(position="XYZ")], [])
        self.assertEqual(rows, [])


class Exclusions(unittest.TestCase):

    def test_blank_av_row_is_excluded_not_emitted_as_null(self):
        rows = transform([nflverse_row(av="")], [])
        self.assertEqual(rows, [])

    def test_blank_position_row_is_excluded(self):
        rows = transform([nflverse_row(position="", av="0")], [])
        self.assertEqual(rows, [])

    def test_pfr_row_with_blank_av_is_excluded(self):
        rows = transform([], [pfr_line(av="")])
        self.assertEqual(rows, [])

    def test_unmapped_nflverse_team_code_is_excluded(self):
        # Defensive: every code in the real 2006-2019 file is in
        # FRANCHISE_CODE, but an unrecognised one should drop, not crash.
        rows = transform([nflverse_row(team="ZZZ")], [])
        self.assertEqual(rows, [])


class MidSeasonTrade(unittest.TestCase):

    def test_trade_produces_one_row_per_franchise(self):
        rows = transform(
            [
                nflverse_row(team="NYG", av="3"),
                nflverse_row(team="DAL", av="4"),
            ],
            [],
        )
        self.assertEqual(len(rows), 2)
        by_franchise = {r.franchise_code: r.av for r in rows}
        self.assertEqual(by_franchise, {"nyg": 3, "dal": 4})


class FranchiseCode(unittest.TestCase):

    def test_relocated_franchise_codes_unify_under_one_pfr_code(self):
        # SD and LAC are the same franchise across the Chargers' move;
        # nflverse carries the period-correct code per season, and both
        # must resolve to PFR's one stable code for that franchise.
        sd_row = transform([nflverse_row(team="SD", season=2015)], [])[0]
        lac_row = transform([nflverse_row(team="LAC", season=2018)], [])[0]
        self.assertEqual(sd_row.franchise_code, lac_row.franchise_code)
        self.assertEqual(sd_row.franchise_code, "sdg")

    def test_pfr_source_rows_keep_their_own_franchise_code(self):
        # The 2020-2025 scrape already keys on PFR's code directly — no
        # translation, unlike nflverse rows.
        rows = transform([], [pfr_line(code="oti")])
        self.assertEqual(rows[0].franchise_code, "oti")


class Determinism(unittest.TestCase):

    def test_rebuilding_the_same_input_twice_is_byte_identical(self):
        nflverse_rows = [
            nflverse_row(team="NYG", playerid="A", av="1"),
            nflverse_row(team="DAL", playerid="B", av="2"),
        ]
        pfr_lines = [pfr_line(code="kan", player_id="C", av="3")]

        first = transform(list(nflverse_rows), list(pfr_lines))
        second = transform(list(reversed(nflverse_rows)), list(reversed(pfr_lines)))
        self.assertEqual(first, second)


class BothSourcesTogether(unittest.TestCase):

    def test_a_player_can_appear_in_both_sources_without_colliding(self):
        # Same player id, same franchise, different seasons — one source
        # covers 2006-2019, the other 2020-, so this is the ordinary case,
        # not an edge case.
        rows = transform(
            [nflverse_row(season=2015, team="KC", playerid="TestPl00")],
            [pfr_line(code="kan", season=2023, player_id="TestPl00")],
        )
        self.assertEqual(len(rows), 2)
        self.assertEqual({r.season for r in rows}, {2015, 2023})

    def test_output_is_sorted_by_season_then_franchise_then_player(self):
        rows = transform(
            [nflverse_row(season=2016, team="DAL", playerid="B")],
            [pfr_line(code="kan", season=2015, player_id="A")],
        )
        self.assertEqual([(r.season, r.franchise_code) for r in rows],
                          [(2015, "kan"), (2016, "dal")])


class HeadshotEmitter(unittest.TestCase):
    """The headshot artifact, which is the second thing a pool build writes.

    Covered here rather than by a build guard because these are properties of
    the emitter itself — what it selects, how it orders, how it quotes — and a
    guard only ever sees one real run's output. Mirrors
    `scripts/player_pool/test_transform.py`'s own HeadshotEmitter, keyed on
    the PFR id this pool already carries instead of a GSIS crosswalk.
    """

    def pool(self):
        return transform(
            [nflverse_row(playerid="a"), nflverse_row(playerid="b"),
             nflverse_row(playerid="c")],
            [],
        )

    def test_emits_only_players_the_pool_can_deal(self):
        shots = {"a": "https://x/a", "b": "https://x/b", "zzz": "https://x/zzz"}
        sql = build_pool.emit_headshot_sql(self.pool(), shots)
        self.assertIn("'a'", sql)
        self.assertIn("'b'", sql)
        self.assertNotIn("zzz", sql)

    def test_a_player_with_no_shot_is_skipped_rather_than_emitted_null(self):
        sql = build_pool.emit_headshot_sql(self.pool(), {"a": "https://x/a"})
        self.assertNotIn("null", sql.lower())
        values = [line for line in sql.splitlines() if line.startswith("  (")]
        self.assertEqual(values, ["  ('a', 'https://x/a');"])

    def test_one_row_per_player_not_per_franchise_season(self):
        rows = transform(
            [nflverse_row(playerid="a", season=2015, team="NYG"),
             nflverse_row(playerid="a", season=2016, team="NYG")],
            [],
        )
        self.assertGreater(len(rows), 1)
        sql = build_pool.emit_headshot_sql(rows, {"a": "https://x/a"})
        self.assertEqual(sql.count("https://x/a"), 1)

    def test_output_is_deterministic_regardless_of_row_order(self):
        rows = self.pool()
        shots = {"a": "https://x/a", "b": "https://x/b", "c": "https://x/c"}
        self.assertEqual(
            build_pool.emit_headshot_sql(rows, shots),
            build_pool.emit_headshot_sql(list(reversed(rows)), shots),
        )

    def test_quotes_are_escaped(self):
        sql = build_pool.emit_headshot_sql(self.pool(), {"a": "https://x/o'brien"})
        self.assertIn("'https://x/o''brien'", sql)

    def test_coverage_floor_fails_the_build_when_the_join_collapses(self):
        with self.assertRaises(build_pool.GuardFailure):
            build_pool.check_headshot_coverage(self.pool(), {})

    def test_coverage_floor_tolerates_a_few_misses(self):
        shots = {"a": "https://x/a", "b": "https://x/b", "c": "https://x/c"}
        self.assertEqual(build_pool.check_headshot_coverage(self.pool(), shots), 1.0)


if __name__ == "__main__":
    unittest.main()
