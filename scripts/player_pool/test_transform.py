"""Tests for the pool transform.

The transform is the only seam here: parsed source rows plus band configuration
in, finished player-weeks out. Fetching, artifact writing and database loading
sit outside it and are covered by the build-time guards instead.

Run with: python3 -m unittest discover scripts/player_pool
"""

import unittest
from decimal import Decimal

import build_pool
from transform import transform

# Bands used by most tests. Deliberately NOT the production values: the
# transform takes bands as an argument precisely so that tuning the real ones
# cannot break these tests, and so that a transform quietly ignoring the
# argument and reaching for a default of its own would fail here.
BANDS = {
    "QB": {"star": (1, 3), "solid": (4, 10), "deep": (11, 20)},
    "RB": {"star": (1, 4), "solid": (5, 12), "deep": (13, 25)},
    "WR": {"star": (1, 2), "solid": (3, 8), "deep": (9, 15)},
    "TE": {"star": (1, 6), "solid": (7, 11), "deep": (12, 16)},
}


def src(**over):
    """One source row, in nflverse's column names."""
    row = {
        "player_id": "00-0000001",
        "player_display_name": "Test Player",
        "position": "RB",
        "season": "2015",
        "week": "1",
        "season_type": "REG",
        "team": "NYG",
        "opponent_team": "DAL",
        "fantasy_points_ppr": "10.0",
    }
    row.update({k: str(v) for k, v in over.items()})
    return row


def season_for(player_id, position, season, points_by_week, **over):
    """A full player-season: one source row per entry in points_by_week."""
    return [
        src(
            player_id=player_id,
            player_display_name=player_id,
            position=position,
            season=season,
            week=week,
            fantasy_points_ppr=points,
            **over,
        )
        for week, points in points_by_week.items()
    ]


def field(rows, name):
    return [getattr(r, name) for r in rows]


class TestTeamCodes(unittest.TestCase):
    """nflverse normalises team codes to the modern franchise. The matchup is
    one of only four recall cues on a card, so they get reversed at load time."""

    def assert_code(self, *, modern, historical, last_historical_season, current=None):
        for season, expected in [
            (last_historical_season, historical),
            (last_historical_season + 1, current or modern),
        ]:
            with self.subTest(season=season, column="team"):
                out = transform(
                    season_for("p1", "RB", season, {1: "10.0"}, team=modern),
                    BANDS,
                )
                self.assertEqual(field(out, "team"), [expected])
            with self.subTest(season=season, column="opponent"):
                out = transform(
                    season_for("p1", "RB", season, {1: "10.0"}, opponent_team=modern),
                    BANDS,
                )
                self.assertEqual(field(out, "opponent"), [expected])

    def test_rams_are_st_louis_through_2015(self):
        self.assert_code(modern="LA", historical="STL", last_historical_season=2015, current="LAR")

    def test_rams_lar_alias_is_also_remapped(self):
        out = transform(season_for("p1", "RB", 2015, {1: "10.0"}, team="LAR"), BANDS)
        self.assertEqual(field(out, "team"), ["STL"])

    def test_chargers_are_san_diego_through_2016(self):
        self.assert_code(modern="LAC", historical="SD", last_historical_season=2016)

    def test_raiders_are_oakland_through_2019(self):
        self.assert_code(modern="LV", historical="OAK", last_historical_season=2019)

    def test_washington_is_never_remapped(self):
        out = transform(season_for("p1", "RB", 2012, {1: "10.0"}, team="WAS"), BANDS)
        self.assertEqual(field(out, "team"), ["WAS"])


class TestFilters(unittest.TestCase):
    def test_playoff_rows_are_excluded(self):
        rows = season_for("p1", "RB", 2015, {1: "10.0"}) + season_for(
            "p1", "RB", 2015, {18: "30.0"}, season_type="POST"
        )
        out = transform(rows, BANDS)
        self.assertEqual(field(out, "week"), [1])

    def test_playoff_points_do_not_reach_the_season_total(self):
        """Playoffs are dropped before aggregation, so they cannot move a rank."""
        rows = (
            season_for("p1", "RB", 2015, {1: "10.0"})
            + season_for("p1", "RB", 2015, {18: "99.0"}, season_type="POST")
            + season_for("p2", "RB", 2015, {1: "50.0"})
        )
        out = transform(rows, BANDS)
        ranks = {r.player_id: r.pos_rank for r in out}
        self.assertEqual(ranks, {"p2": 1, "p1": 2})

    def test_non_skill_positions_are_excluded(self):
        rows = []
        for pos in ["K", "DE", "CB", "LB", "FB", "P"]:
            rows += season_for(f"x{pos}", pos, 2015, {1: "10.0"})
        rows += season_for("p1", "RB", 2015, {1: "10.0"})
        out = transform(rows, BANDS)
        self.assertEqual(field(out, "player_id"), ["p1"])

    def test_a_zero_point_week_survives(self):
        """Duds are the point. A player who left injured is still a lot."""
        out = transform(season_for("p1", "RB", 2015, {1: "0.0", 2: "20.0"}), BANDS)
        self.assertEqual(field(out, "points"), [Decimal("0.0"), Decimal("20.0")])

    def test_a_negative_week_survives(self):
        out = transform(season_for("p1", "RB", 2015, {1: "-6.6", 2: "20.0"}), BANDS)
        self.assertEqual(field(out, "points"), [Decimal("-6.6"), Decimal("20.0")])

    def test_an_all_zero_player_season_still_produces_rows(self):
        rows = season_for("p1", "RB", 2015, {1: "0.0"}) + season_for(
            "p2", "RB", 2015, {1: "20.0"}
        )
        out = transform(rows, BANDS)
        self.assertIn("p1", field(out, "player_id"))


class TestAggregation(unittest.TestCase):
    def test_a_midseason_trade_aggregates_into_one_season_total(self):
        rows = season_for("mover", "RB", 2015, {1: "20.0"}, team="NYG") + season_for(
            "mover", "RB", 2015, {2: "20.0"}, team="SF"
        )
        rows += season_for("rival", "RB", 2015, {1: "30.0"})
        out = transform(rows, BANDS)
        ranks = {r.player_id: r.pos_rank for r in out}
        # 40 across two teams beats 30, which a per-team total would not.
        self.assertEqual(ranks, {"mover": 1, "rival": 2})

    def test_each_week_keeps_its_own_team(self):
        rows = season_for("mover", "RB", 2015, {1: "20.0"}, team="NYG") + season_for(
            "mover", "RB", 2015, {2: "20.0"}, team="SF"
        )
        out = transform(rows, BANDS)
        self.assertEqual({r.week: r.team for r in out}, {1: "NYG", 2: "SF"})

    def test_ranking_is_within_position_not_across_positions(self):
        rows = season_for("qb", "QB", 2015, {1: "50.0"}) + season_for(
            "rb", "RB", 2015, {1: "10.0"}
        )
        out = transform(rows, BANDS)
        self.assertEqual({r.player_id: r.pos_rank for r in out}, {"qb": 1, "rb": 1})

    def test_ranking_is_within_season_not_across_seasons(self):
        rows = season_for("a", "RB", 2014, {1: "10.0"}) + season_for(
            "b", "RB", 2015, {1: "50.0"}
        )
        out = transform(rows, BANDS)
        self.assertEqual({r.player_id: r.pos_rank for r in out}, {"a": 1, "b": 1})

    def test_points_are_rounded_to_one_decimal(self):
        """The source carries float noise; the column is numeric(5,1)."""
        out = transform(season_for("p1", "RB", 2015, {1: "27.62000000000001"}), BANDS)
        self.assertEqual(field(out, "points"), [Decimal("27.6")])

    def test_rounding_is_half_up_to_match_postgres(self):
        out = transform(season_for("p1", "RB", 2015, {1: "10.25", 2: "10.35"}), BANDS)
        self.assertEqual(field(out, "points"), [Decimal("10.3"), Decimal("10.4")])

    def test_a_players_display_name_is_carried_through(self):
        rows = [src(player_display_name="Saquon Barkley")]
        out = transform(rows, BANDS)
        self.assertEqual(field(out, "display_name"), ["Saquon Barkley"])


class TestTiering(unittest.TestCase):
    def build_ranked_field(self, position, count, season=2015):
        """`count` players at one position, descending totals, so that the
        player with id QB001 ranks 1, QB002 ranks 2, and so on."""
        rows = []
        for i in range(1, count + 1):
            rows += season_for(f"{position}{i:03d}", position, season,
                               {1: str(1000 - i)})
        return rows

    def test_band_edges_land_in_the_expected_tier(self):
        for position, bands in BANDS.items():
            deep_hi = bands["deep"][1]
            out = transform(self.build_ranked_field(position, deep_hi), BANDS)
            tier_by_rank = {r.pos_rank: r.tier for r in out}
            for tier, (lo, hi) in bands.items():
                with self.subTest(position=position, tier=tier):
                    self.assertEqual(tier_by_rank[lo], tier, f"rank {lo} lower edge")
                    self.assertEqual(tier_by_rank[hi], tier, f"rank {hi} upper edge")

    def test_a_season_ranked_past_the_last_band_is_dropped(self):
        for position, bands in BANDS.items():
            deep_hi = bands["deep"][1]
            with self.subTest(position=position):
                out = transform(self.build_ranked_field(position, deep_hi + 3), BANDS)
                self.assertEqual(max(r.pos_rank for r in out), deep_hi)

    def test_a_dropped_season_loses_every_one_of_its_weeks(self):
        rows = self.build_ranked_field("QB", 32)
        rows += season_for("zzz", "QB", 2015, {1: "1.0", 2: "1.0", 3: "1.0"})
        out = transform(rows, BANDS)
        self.assertNotIn("zzz", field(out, "player_id"))

    def test_no_row_is_ever_emitted_untiered(self):
        out = transform(self.build_ranked_field("WR", 70), BANDS)
        self.assertEqual(set(field(out, "tier")), {"star", "solid", "deep"})

    def test_bands_apply_per_position(self):
        """Rank 4 is a solid QB but a star RB under these bands."""
        rows = self.build_ranked_field("QB", 4) + self.build_ranked_field("RB", 4)
        out = transform(rows, BANDS)
        at_4 = {r.position: r.tier for r in out if r.pos_rank == 4}
        self.assertEqual(at_4, {"QB": "solid", "RB": "star"})

    def test_a_gap_between_bands_drops_the_ranks_inside_it(self):
        bands = {"RB": {"star": (1, 2), "solid": (5, 6), "deep": (7, 8)}}
        out = transform(self.build_ranked_field("RB", 8), bands)
        self.assertEqual(sorted(field(out, "pos_rank")), [1, 2, 5, 6, 7, 8])

    def test_the_whole_season_is_tiered_from_one_rank(self):
        rows = season_for("p1", "RB", 2015, {1: "10.0", 2: "0.0", 3: "40.0"})
        out = transform(rows, BANDS)
        self.assertEqual(set(field(out, "tier")), {"star"})
        self.assertEqual(set(field(out, "pos_rank")), {1})


class TestDeterminism(unittest.TestCase):
    def test_equal_totals_break_ties_by_player_id_ascending(self):
        rows = (
            season_for("bbb", "RB", 2015, {1: "10.0"})
            + season_for("aaa", "RB", 2015, {1: "10.0"})
            + season_for("ccc", "RB", 2015, {1: "10.0"})
        )
        out = transform(rows, BANDS)
        self.assertEqual({r.player_id: r.pos_rank for r in out},
                         {"aaa": 1, "bbb": 2, "ccc": 3})

    def test_input_order_does_not_change_the_output(self):
        rows = (
            season_for("bbb", "RB", 2015, {2: "10.0", 1: "30.0"})
            + season_for("aaa", "RB", 2015, {1: "10.0"})
            + season_for("ccc", "WR", 2016, {3: "10.0"})
        )
        self.assertEqual(transform(rows, BANDS), transform(list(reversed(rows)), BANDS))

    def test_output_is_ordered_by_season_week_then_player(self):
        rows = (
            season_for("bbb", "RB", 2016, {1: "10.0"})
            + season_for("aaa", "RB", 2015, {2: "10.0"})
            + season_for("ccc", "RB", 2015, {1: "10.0"})
        )
        out = transform(rows, BANDS)
        self.assertEqual(
            [(r.season, r.week, r.player_id) for r in out],
            [(2015, 1, "ccc"), (2015, 2, "aaa"), (2016, 1, "bbb")],
        )


class TestRankMetric(unittest.TestCase):
    """Ranking on season total means a star who missed six games ranks like a
    mediocre full-season one. Points-per-game is the tuning alternative."""

    def rows(self):
        return season_for("injured", "RB", 2015, {1: "30.0", 2: "30.0"}) + season_for(
            "plodder", "RB", 2015, {w: "10.0" for w in range(1, 8)}
        )

    def test_total_ranks_the_full_season_player_higher(self):
        out = transform(self.rows(), BANDS, rank_by="total")
        self.assertEqual({r.player_id: r.pos_rank for r in out},
                         {"plodder": 1, "injured": 2})

    def test_per_game_ranks_the_injured_star_higher(self):
        out = transform(self.rows(), BANDS, rank_by="per_game")
        self.assertEqual({r.player_id: r.pos_rank for r in out},
                         {"injured": 1, "plodder": 2})

    def test_an_unknown_rank_metric_is_rejected(self):
        with self.assertRaises(ValueError):
            transform(self.rows(), BANDS, rank_by="vibes")


class TestPositionChanges(unittest.TestCase):
    """A player listed at two positions in one season gets one season position,
    so that position, pos_rank and tier on a card always agree."""

    def test_the_most_played_position_wins(self):
        """TE loses the alphabetical tie-break, so it can only win here on
        count — which is what stops this passing vacuously."""
        rows = season_for("hill", "TE", 2015, {1: "10.0", 2: "10.0"}) + season_for(
            "hill", "QB", 2015, {3: "10.0"}
        )
        out = transform(rows, BANDS)
        self.assertEqual(set(field(out, "position")), {"TE"})

    def test_an_even_split_breaks_alphabetically(self):
        rows = season_for("hill", "QB", 2015, {1: "10.0"}) + season_for(
            "hill", "TE", 2015, {2: "10.0"}
        )
        out = transform(rows, BANDS)
        self.assertEqual(set(field(out, "position")), {"QB"})

    def test_all_of_a_players_weeks_count_toward_the_one_season_total(self):
        rows = season_for("hill", "QB", 2015, {1: "10.0", 2: "10.0"}) + season_for(
            "hill", "TE", 2015, {3: "10.0"}
        )
        rows += season_for("rival", "QB", 2015, {1: "25.0"})
        out = transform(rows, BANDS)
        self.assertEqual({r.player_id: r.pos_rank for r in out}["hill"], 1)


class HeadshotEmitter(unittest.TestCase):
    """The headshot artifact, which is the second thing a pool build writes.

    Covered here rather than by a build guard because these are properties of
    the emitter itself — what it selects, how it orders, how it quotes — and a
    guard only ever sees one real run's output.
    """

    def pool(self):
        return transform(
            season_for("a", "QB", 2015, {1: "30.0"})
            + season_for("b", "QB", 2015, {1: "20.0"})
            + season_for("c", "QB", 2015, {1: "10.0"}),
            BANDS,
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

    def test_one_row_per_player_not_per_player_week(self):
        rows = transform(season_for("a", "QB", 2015, {1: "30.0", 2: "20.0", 3: "1.0"}), BANDS)
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
