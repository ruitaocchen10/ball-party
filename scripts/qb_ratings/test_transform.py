"""Tests for the ratings transform.

The transform is the only seam here: source rows and a Config in, finished
values out. Every test passes its own tuning, so retuning the real numbers in
config.py cannot break them, and none reads a production coefficient.

Fetching, guards and artifact writing sit outside it and are covered by the
build's own guards instead.

Run with: python3 -m unittest discover scripts/qb_ratings
"""

import random
import unittest

from transform import (
    CAST, TRAITS, Config, Expectation, MaddenRating, Override, QbSeason,
    RosterPlayer, apply_overrides, expectation_violations, percentiles,
    qb_seasons_from_weeks, transform,
)

# ------------------------------------------------------------------ helpers --


def cfg(**over):
    """A tiny tuning where each trait reads one stat metric and one Madden
    attribute, so a test can say exactly which input it is moving."""
    base = dict(
        min_attempts=150,
        weights={slot: (50, 50) for slot in TRAITS + (CAST,)},
        value_floor=0,
        value_ceiling=99,
        madden_attrs={
            "accuracy": {"acc": 1}, "arm_talent": {"arm": 1}, "mobility": {"mob": 1},
            "iq": {"iq": 1}, "build": {"bld": 1},
        },
        stat_metrics={
            "accuracy": {"comp_pct": 1}, "arm_talent": {"air_yards_per_att": 1},
            "mobility": {"rush_ypc": 1}, "iq": {"int_rate": 1}, "build": {"height": 1},
        },
        shrinkage={},
        cast_offense_share=0.7,
        cast_slots={"WR": ("offense", 1, 1.0), "CB": ("defense", 1, 1.0)},
        cast_attr="ovr",
    )
    base.update(over)
    return Config(**base)


def only(weights):
    """Every slot at the same (Madden, stats) weight."""
    return {slot: weights for slot in TRAITS + (CAST,)}


def qb(player_id="QbOne00", season=2015, franchise="nyg", **over):
    row = dict(
        franchise_code=franchise, season=season, player_id=player_id,
        display_name=player_id, games=16, team_games=16, attempts=500,
        completions=300, pass_yards=3500.0, air_yards=3500.0, explosive=50,
        cpoe_sum=0.0, pass_epa=0.0, interceptions=10, sacks=30, fumbles_lost=3, carries=50,
        rush_yards=200.0, rush_first_downs=10, rush_epa=0.0,
        height=75.0, weight=220.0,
    )
    row.update(over)
    return QbSeason(**row)


def madden(edition, player_id, position="QB", **ratings):
    return MaddenRating(edition, player_id, position, ratings)


def value(ratings, player_id, trait, season=2015):
    (row,) = [r for r in ratings.qb_rows if r.player_id == player_id and r.season == season]
    return getattr(row, trait)


def cast_value(ratings, franchise, season=2015):
    (row,) = [r for r in ratings.team_rows
              if r.franchise_code == franchise and r.season == season]
    return row.supporting_cast


def team(franchise, season=2015, wr_av=5, cb_av=5, wr="wr", cb="cb"):
    return [RosterPlayer(franchise, season, f"{franchise}-{wr}", "WR", wr_av),
            RosterPlayer(franchise, season, f"{franchise}-{cb}", "CB", cb_av)]


def week(team="NYG", player="00-1", week=1, position="QB", season=2015,
         season_type="REG", **over):
    row = {
        "season_type": season_type, "season": str(season), "week": str(week),
        "team": team, "player_id": player, "position": position,
        "attempts": "30", "completions": "20", "passing_yards": "250",
        "passing_air_yards": "200", "passing_20": "3", "passing_cpoe": "0",
        "passing_interceptions": "1", "sacks_suffered": "2", "sack_fumbles_lost": "0",
        "rushing_fumbles_lost": "0", "carries": "3", "rushing_yards": "10",
        "rushing_first_downs": "0", "rushing_epa": "0", "passing_epa": "0",
    }
    row.update({k: str(v) for k, v in over.items()})
    return row


PEOPLE = {"00-1": ("QbOne00", "Q One", 75.0, 220.0),
          "00-2": ("QbTwo00", "Q Two", 73.0, 210.0),
          "00-3": ("QbThr00", "Q Three", 77.0, 230.0)}
FRANCHISES = {"NYG": "nyg", "DAL": "dal"}


# ------------------------------------------------------ ranking within season --


class Percentiles(unittest.TestCase):

    def test_ranks_span_zero_to_one(self):
        self.assertEqual(percentiles({"a": 1, "b": 5, "c": 3}), {"a": 0.0, "b": 1.0, "c": 0.5})

    def test_ties_share_their_average_rank(self):
        ranks = percentiles({"a": 1, "b": 2, "c": 2, "d": 3})
        self.assertEqual(ranks["b"], ranks["c"])
        self.assertEqual(ranks["b"], 0.5)

    def test_a_lone_value_ranks_in_the_middle(self):
        self.assertEqual(percentiles({"a": 7}), {"a": 0.5})

    def test_order_of_arrival_does_not_matter(self):
        items = [("a", 2), ("b", 2), ("c", 1), ("d", 9)]
        shuffled = list(items)
        random.Random(3).shuffle(shuffled)
        self.assertEqual(percentiles(dict(items)), percentiles(dict(shuffled)))


class WithinSeasonRanking(unittest.TestCase):

    def test_each_season_is_ranked_against_itself(self):
        # 2011's best passer is worse than 2010's worst, and still tops 2011.
        rows = [
            qb("a10", 2010, completions=350), qb("b10", 2010, completions=380),
            qb("a11", 2011, completions=250), qb("b11", 2011, completions=280),
        ]
        out = transform(rows, [], [], cfg(weights=only((0, 100))))
        self.assertEqual(value(out, "a10", "accuracy", 2010), 0)
        self.assertEqual(value(out, "b10", "accuracy", 2010), 99)
        self.assertEqual(value(out, "a11", "accuracy", 2011), 0)
        self.assertEqual(value(out, "b11", "accuracy", 2011), 99)

    def test_a_lower_is_better_metric_ranks_the_low_rate_first(self):
        rows = [qb("safe", interceptions=5), qb("wild", interceptions=25)]
        out = transform(rows, [], [], cfg(weights=only((0, 100))))
        self.assertGreater(value(out, "safe", "iq"), value(out, "wild", "iq"))

    def test_epa_per_dropback_counts_the_sacks_in_its_denominator(self):
        # Same passing EPA total: the one who was sacked more took it over more dropbacks.
        rows = [qb("clean", pass_epa=100.0, sacks=0), qb("sacked", pass_epa=100.0, sacks=100)]
        out = transform(rows, [], [], cfg(weights=only((0, 100)),
                                          stat_metrics={**cfg().stat_metrics, "iq": {"epa_per_dropback": 1}}))
        self.assertGreater(value(out, "clean", "iq"), value(out, "sacked", "iq"))

    def test_iq_leans_on_epa_when_it_is_the_heavier_stat_input(self):
        # "epa" is better on EPA but worse on turnovers; with EPA the heavy input
        # it is the higher IQ, and with the turnover metric heavy it is not.
        rows = [qb("epa", pass_epa=150.0, interceptions=20), qb("safe", pass_epa=20.0, interceptions=5)]
        heavy_epa = {**cfg().stat_metrics, "iq": {"epa_per_dropback": 0.8, "int_rate": 0.2}}
        heavy_int = {**cfg().stat_metrics, "iq": {"epa_per_dropback": 0.2, "int_rate": 0.8}}
        a = transform(rows, [], [], cfg(weights=only((0, 100)), stat_metrics=heavy_epa))
        b = transform(rows, [], [], cfg(weights=only((0, 100)), stat_metrics=heavy_int))
        self.assertGreater(value(a, "epa", "iq"), value(a, "safe", "iq"))
        self.assertGreater(value(b, "safe", "iq"), value(b, "epa", "iq"))

    def test_the_value_band_is_an_input(self):
        rows = [qb("lo", completions=250), qb("hi", completions=350)]
        out = transform(rows, [], [], cfg(weights=only((0, 100)),
                                          value_floor=40, value_ceiling=90))
        self.assertEqual((value(out, "lo", "accuracy"), value(out, "hi", "accuracy")), (40, 90))

    def test_a_small_sample_is_pulled_toward_the_league_rate(self):
        # Hot on 20 attempts vs solid on 400: with a prior worth 400 attempts
        # the tiny sample is dragged back below the proven passer.
        rows = [
            qb("hot", attempts=20, completions=20),
            qb("solid", attempts=400, completions=280),
            qb("mid", attempts=400, completions=240),
        ]
        raw = transform(rows, [], [], cfg(weights=only((0, 100))))
        shrunk = transform(rows, [], [], cfg(weights=only((0, 100)),
                                             shrinkage={"comp_pct": 400}))
        self.assertGreater(value(raw, "hot", "accuracy"), value(raw, "solid", "accuracy"))
        self.assertLess(value(shrunk, "hot", "accuracy"), value(shrunk, "solid", "accuracy"))


# --------------------------------------------------------------------- blend --


def three_way_split():
    """A: best Madden, worst stats. B: middle on both. C: worst Madden, best stats."""
    rows = [qb("A", completions=200), qb("B", completions=300), qb("C", completions=400)]
    ratings = [madden(2016, "A", acc=90), madden(2016, "B", acc=70), madden(2016, "C", acc=50)]
    return rows, ratings


class Blend(unittest.TestCase):

    def test_madden_only_follows_the_madden_ranking(self):
        rows, ratings = three_way_split()
        out = transform(rows, ratings, [], cfg(weights=only((100, 0))))
        self.assertEqual([value(out, k, "accuracy") for k in "ABC"], [99, 50, 0])

    def test_stats_only_follows_the_stat_ranking(self):
        rows, ratings = three_way_split()
        out = transform(rows, ratings, [], cfg(weights=only((0, 100))))
        self.assertEqual([value(out, k, "accuracy") for k in "ABC"], [0, 50, 99])

    def test_the_weights_split_the_difference(self):
        rows, ratings = three_way_split()
        out = transform(rows, ratings, [], cfg(weights=only((75, 25))))
        self.assertEqual([value(out, k, "accuracy") for k in "ABC"], [74, 50, 25])

    def test_each_trait_reads_its_own_weights(self):
        rows = [
            qb("A", completions=200, interceptions=5),
            qb("B", completions=400, interceptions=25),
        ]
        ratings = [madden(2016, "A", acc=90, iq=90), madden(2016, "B", acc=50, iq=50)]
        weights = {**only((50, 50)), "accuracy": (100, 0), "iq": (0, 100)}
        out = transform(rows, ratings, [], cfg(weights=weights))
        self.assertEqual(value(out, "A", "accuracy"), 99)   # Madden alone: A is better
        self.assertEqual(value(out, "B", "iq"), 0)          # stats alone: B has more picks

    def test_a_trait_averages_its_components_by_their_weights(self):
        # Two Madden attributes for one trait: the heavier one decides.
        rows = [qb("A"), qb("B")]
        ratings = [madden(2016, "A", acc=90, acc2=10), madden(2016, "B", acc=10, acc2=90)]
        heavy_first = cfg(weights=only((100, 0)), madden_attrs={
            **cfg().madden_attrs, "accuracy": {"acc": 3, "acc2": 1}})
        heavy_second = cfg(weights=only((100, 0)), madden_attrs={
            **cfg().madden_attrs, "accuracy": {"acc": 1, "acc2": 3}})
        self.assertGreater(value(transform(rows, ratings, [], heavy_first), "A", "accuracy"),
                           value(transform(rows, ratings, [], heavy_first), "B", "accuracy"))
        self.assertGreater(value(transform(rows, ratings, [], heavy_second), "B", "accuracy"),
                           value(transform(rows, ratings, [], heavy_second), "A", "accuracy"))

    def test_an_attribute_a_player_lacks_is_not_counted_as_zero(self):
        rows = [qb("X"), qb("Y"), qb("Z")]
        ratings = [
            madden(2016, "X", acc=50, acc2=50),
            madden(2016, "Y", acc=60),             # no second attribute at all
            madden(2016, "Z", acc=40, acc2=40),
        ]
        conf = cfg(weights=only((100, 0)), madden_attrs={
            **cfg().madden_attrs, "accuracy": {"acc": 1, "acc2": 1}})
        out = transform(rows, ratings, [], conf)
        self.assertGreaterEqual(value(out, "Y", "accuracy"), value(out, "X", "accuracy"))

    def test_a_quarterback_with_no_madden_rating_is_all_stats(self):
        rows = [qb("rated", completions=200), qb("unrated", completions=400)]
        ratings = [madden(2016, "rated", acc=99)]
        out = transform(rows, ratings, [], cfg(weights=only((100, 0))))
        # Madden weight 100, but the unrated row has nothing to weigh: it is
        # ranked on stats, against a pool that is only itself on the Madden side.
        self.assertEqual(value(out, "unrated", "accuracy"), 99)


# ------------------------------------------------------------ edition fallback --


class EditionFallback(unittest.TestCase):

    def test_the_edition_after_the_season_rates_it(self):
        rows = [qb("A"), qb("B")]
        ratings = [
            madden(2016, "A", acc=90), madden(2016, "B", acc=10),   # after: A better
            madden(2015, "A", acc=10), madden(2015, "B", acc=90),   # pre-season: reversed
        ]
        out = transform(rows, ratings, [], cfg(weights=only((100, 0))))
        self.assertGreater(value(out, "A", "accuracy"), value(out, "B", "accuracy"))

    def test_a_player_the_later_edition_lacks_falls_back_to_the_pre_season_one(self):
        rows = [qb("A"), qb("B"), qb("C")]
        ratings = [
            madden(2016, "B", acc=50), madden(2016, "C", acc=10),
            madden(2015, "A", acc=99),                              # only pre-season
        ]
        out = transform(rows, ratings, [], cfg(weights=only((100, 0))))
        self.assertEqual(value(out, "A", "accuracy"), 99)

    def test_a_later_edition_without_the_attribute_falls_back_for_that_trait_only(self):
        rows = [qb("A"), qb("B")]
        ratings = [
            madden(2016, "A", other=1),                             # listed, no `acc`
            madden(2016, "B", acc=20),
            madden(2015, "A", acc=90),
        ]
        out = transform(rows, ratings, [], cfg(weights=only((100, 0))))
        self.assertGreater(value(out, "A", "accuracy"), value(out, "B", "accuracy"))

    def test_the_edition_key_is_the_season_plus_one_not_the_season(self):
        # An edition two seasons on says nothing about this one.
        rows = [qb("A"), qb("B")]
        ratings = [madden(2017, "A", acc=99), madden(2017, "B", acc=1)]
        out = transform(rows, ratings, [], cfg(weights=only((100, 0)), ))
        # Neither has a usable Madden input, so both are ranked on identical
        # stats: a tie, not an echo of the 2017 edition.
        self.assertEqual(value(out, "A", "accuracy"), value(out, "B", "accuracy"))


# ------------------------------------------------------------ Supporting Cast --


class SupportingCast(unittest.TestCase):

    def two_teams(self):
        """nyg: great weapon, poor corner. dal: the reverse."""
        rosters = team("nyg", wr_av=15, cb_av=1) + team("dal", wr_av=1, cb_av=15)
        ratings = [madden(2016, "nyg-wr", "WR", ovr=95), madden(2016, "nyg-cb", "CB", ovr=50),
                   madden(2016, "dal-wr", "WR", ovr=50), madden(2016, "dal-cb", "CB", ovr=95)]
        return rosters, ratings

    def test_offense_outweighs_defense_by_the_configured_split(self):
        rosters, ratings = self.two_teams()
        heavy_offense = transform([], ratings, rosters, cfg(cast_offense_share=0.7))
        self.assertGreater(cast_value(heavy_offense, "nyg"), cast_value(heavy_offense, "dal"))
        heavy_defense = transform([], ratings, rosters, cfg(cast_offense_share=0.3))
        self.assertGreater(cast_value(heavy_defense, "dal"), cast_value(heavy_defense, "nyg"))

    def test_an_even_split_ties_a_mirror_image(self):
        rosters, ratings = self.two_teams()
        out = transform([], ratings, rosters, cfg(cast_offense_share=0.5))
        self.assertEqual(cast_value(out, "nyg"), cast_value(out, "dal"))

    def test_each_half_blends_madden_and_season_value_by_the_cast_weights(self):
        # nyg has the better AV, dal the better Madden rating, at the same slots.
        rosters = team("nyg", wr_av=15, cb_av=15) + team("dal", wr_av=1, cb_av=1)
        ratings = [madden(2016, "nyg-wr", "WR", ovr=50), madden(2016, "nyg-cb", "CB", ovr=50),
                   madden(2016, "dal-wr", "WR", ovr=95), madden(2016, "dal-cb", "CB", ovr=95)]
        madden_only = transform([], ratings, rosters, cfg(weights=only((100, 0))))
        stats_only = transform([], ratings, rosters, cfg(weights=only((0, 100))))
        self.assertGreater(cast_value(madden_only, "dal"), cast_value(madden_only, "nyg"))
        self.assertGreater(cast_value(stats_only, "nyg"), cast_value(stats_only, "dal"))

    def test_the_cast_uses_the_edition_after_the_season(self):
        rosters = team("nyg", wr_av=1, cb_av=1) + team("dal", wr_av=1, cb_av=1)
        ratings = [madden(2016, "nyg-wr", "WR", ovr=90), madden(2015, "nyg-wr", "WR", ovr=10),
                   madden(2016, "dal-wr", "WR", ovr=50), madden(2015, "dal-wr", "WR", ovr=99)]
        out = transform([], ratings, rosters,
                        cfg(weights=only((100, 0)), cast_offense_share=1.0))
        self.assertGreater(cast_value(out, "nyg"), cast_value(out, "dal"))

    def test_only_the_top_n_at_a_slot_count(self):
        # One star and two scrubs vs three solid: with only the top 1 counted the
        # star team wins, with the top 3 counted the depth team does.
        star = [RosterPlayer("nyg", 2015, f"s{i}", "WR", av)
                for i, av in enumerate((20, 1, 1))]
        depth = [RosterPlayer("dal", 2015, f"d{i}", "WR", 8) for i in range(3)]
        for top_n, winner in ((1, "nyg"), (3, "dal")):
            conf = cfg(weights=only((0, 100)), cast_offense_share=1.0,
                       cast_slots={"WR": ("offense", top_n, 1.0)})
            out = transform([], [], star + depth, conf)
            loser = "dal" if winner == "nyg" else "nyg"
            self.assertGreater(cast_value(out, winner), cast_value(out, loser), top_n)

    def test_team_seasons_are_ranked_within_their_season(self):
        rosters = (team("nyg", 2010, wr_av=15) + team("dal", 2010, wr_av=1)
                   + team("nyg", 2011, wr_av=2) + team("dal", 2011, wr_av=9))
        out = transform([], [], rosters, cfg(weights=only((0, 100)), cast_offense_share=1.0))
        self.assertEqual(cast_value(out, "nyg", 2010), cast_value(out, "dal", 2011))


# ------------------------------------------------------------------ aggregate --


class Aggregation(unittest.TestCase):

    def build(self, rows, min_attempts=150):
        return qb_seasons_from_weeks(rows, PEOPLE, FRANCHISES, min_attempts)

    def test_the_attempts_cutoff_is_inclusive(self):
        rows = [week(player="00-1", week=w, attempts=50) for w in (1, 2, 3)]      # 150
        rows += [week(player="00-2", week=w, attempts=50) for w in (1, 2)]
        rows += [week(player="00-2", week=3, attempts=49)]                        # 149
        out = self.build(rows)
        self.assertEqual([q.player_id for q in out], ["QbOne00"])

    def test_a_one_start_season_does_not_qualify(self):
        self.assertEqual(self.build([week(player="00-1", attempts=40)]), [])

    def test_a_quarterback_on_two_teams_is_one_row_per_team(self):
        rows = [week(team="NYG", week=w, attempts=100) for w in (1, 2)]
        rows += [week(team="DAL", week=w, attempts=100) for w in (3, 4)]
        out = self.build(rows)
        self.assertEqual(sorted(q.franchise_code for q in out), ["dal", "nyg"])
        self.assertTrue(all(q.attempts == 200 for q in out))

    def test_the_postseason_is_ignored(self):
        rows = [week(week=w, attempts=100) for w in (1, 2)]
        rows += [week(week=19, attempts=100, season_type="POST")]
        (q,) = self.build(rows)
        self.assertEqual((q.attempts, q.games), (200, 2))

    def test_team_games_count_every_regular_season_week_the_team_played(self):
        rows = [week(player="00-1", week=w, attempts=100) for w in (1, 2)]
        # A receiver's rows are how the team's other weeks show up.
        rows += [week(player="00-9", position="WR", week=w, attempts=0) for w in (1, 2, 3, 4)]
        (q,) = self.build(rows)
        self.assertEqual((q.games, q.team_games), (2, 4))

    def test_cpoe_is_weighted_by_attempts(self):
        rows = [week(week=1, attempts=100, passing_cpoe=10),
                week(week=2, attempts=50, passing_cpoe=-4)]
        (q,) = self.build(rows)
        self.assertEqual(q.cpoe_sum, 100 * 10 + 50 * -4)

    def test_the_weekly_passing_epa_is_summed_into_the_season(self):
        rows = [week(week=1, attempts=100, passing_epa=12.5),
                week(week=2, attempts=100, passing_epa=-2.5)]
        (q,) = self.build(rows)
        self.assertEqual(q.pass_epa, 10.0)

    def test_blank_cells_count_as_zero(self):
        rows = [week(week=1, attempts=200, passing_cpoe="NA", rushing_epa="", passing_epa="NA")]
        (q,) = self.build(rows)
        self.assertEqual((q.cpoe_sum, q.rush_epa, q.pass_epa), (0, 0, 0))

    def test_an_unresolvable_id_stops_the_build(self):
        with self.assertRaises(ValueError):
            self.build([week(player="00-404", attempts=200)])

    def test_an_unknown_team_stops_the_build(self):
        with self.assertRaises(ValueError):
            self.build([week(team="XXX", attempts=200)])

    def test_the_cutoff_is_an_input(self):
        rows = [week(attempts=100)]
        self.assertEqual(len(self.build(rows, min_attempts=100)), 1)
        self.assertEqual(len(self.build(rows, min_attempts=101)), 0)


# ------------------------------------------------------------------ overrides --


class Overrides(unittest.TestCase):

    def setUp(self):
        rows = [qb("A"), qb("B")]
        self.ratings = transform(rows, [], team("nyg") + team("dal"),
                                 cfg(weights=only((0, 100))))

    def test_an_override_replaces_a_quarterback_value(self):
        out = apply_overrides(self.ratings, [Override("nyg", 2015, "A", "mobility", 88)])
        self.assertEqual(value(out, "A", "mobility"), 88)

    def test_the_other_values_of_that_row_are_untouched(self):
        out = apply_overrides(self.ratings, [Override("nyg", 2015, "A", "mobility", 88)])
        before = [r for r in self.ratings.qb_rows if r.player_id == "A"][0]
        after = [r for r in out.qb_rows if r.player_id == "A"][0]
        self.assertEqual((after.accuracy, after.iq), (before.accuracy, before.iq))

    def test_an_override_replaces_a_supporting_cast_value(self):
        out = apply_overrides(self.ratings, [Override("dal", 2015, "", CAST, 12)])
        self.assertEqual(cast_value(out, "dal"), 12)

    def test_transform_applies_the_overrides_it_is_given(self):
        out = transform([qb("A")], [], team("nyg"), cfg(),
                        overrides=[Override("nyg", 2015, "A", "build", 7)])
        self.assertEqual(value(out, "A", "build"), 7)

    def test_an_override_for_a_row_that_does_not_exist_is_an_error(self):
        with self.assertRaises(ValueError):
            apply_overrides(self.ratings, [Override("nyg", 2015, "nobody", "mobility", 50)])

    def test_an_override_outside_the_scale_is_an_error(self):
        with self.assertRaises(ValueError):
            apply_overrides(self.ratings, [Override("nyg", 2015, "A", "mobility", 100)])

    def test_an_override_for_an_unknown_slot_is_an_error(self):
        with self.assertRaises(ValueError):
            apply_overrides(self.ratings, [Override("nyg", 2015, "A", "charisma", 50)])


# ------------------------------------------------------------ sanity guards --


class KnownQuarterbackChecks(unittest.TestCase):

    def setUp(self):
        rows = [qb("runner", rush_yards=900.0, carries=100), qb("statue", rush_yards=50.0)]
        self.ratings = transform(rows, [], team("nyg"), cfg(weights=only((0, 100))))

    def test_values_inside_their_band_pass(self):
        checks = [Expectation("runner", 2015, "mobility", 90, 99),
                  Expectation("statue", 2015, "mobility", 0, 10)]
        self.assertEqual(expectation_violations(self.ratings, checks), [])

    def test_a_value_outside_its_band_is_reported_with_its_note(self):
        checks = [Expectation("statue", 2015, "mobility", 60, 99, note="should run")]
        (problem,) = expectation_violations(self.ratings, checks)
        self.assertIn("statue 2015 mobility", problem)
        self.assertIn("should run", problem)

    def test_a_check_for_a_missing_row_is_a_violation_not_a_pass(self):
        checks = [Expectation("nobody", 2015, "mobility", 0, 99)]
        self.assertEqual(len(expectation_violations(self.ratings, checks)), 1)

    def test_a_supporting_cast_can_be_checked(self):
        checks = [Expectation("", 2015, CAST, 0, 99, franchise_code="nyg"),
                  Expectation("", 2015, CAST, 0, 99, franchise_code="xxx")]
        problems = expectation_violations(self.ratings, checks)
        self.assertEqual(len(problems), 1)

    def test_a_check_can_pin_a_team_when_a_player_threw_for_two(self):
        rows = [qb("mover", franchise="nyg", rush_yards=900.0),
                qb("mover", franchise="dal", rush_yards=10.0), qb("other", franchise="nyg")]
        ratings = transform(rows, [], team("nyg") + team("dal"),
                            cfg(weights=only((0, 100))))
        pinned = [Expectation("mover", 2015, "mobility", 90, 99, franchise_code="nyg")]
        self.assertEqual(expectation_violations(ratings, pinned), [])


# ---------------------------------------------------------------- determinism --


class Determinism(unittest.TestCase):

    def test_reordering_the_source_does_not_change_the_output(self):
        rows = [qb(f"q{i}", season=2010 + i % 3, franchise="nyg" if i % 2 else "dal",
                   completions=200 + 7 * i, interceptions=5 + i % 5, height=70.0 + i % 6)
                for i in range(12)]
        ratings = [madden(2011 + i % 3, f"q{i}", acc=50 + i, iq=40 + 3 * i, arm=60 - i,
                          mob=30 + i, bld=45 + i) for i in range(12)]
        rosters = [p for s in (2010, 2011, 2012) for f in ("nyg", "dal")
                   for p in team(f, s, wr_av=s % 7 + len(f))]
        first = transform(rows, ratings, rosters, cfg())
        shuffled = [list(x) for x in (rows, ratings, rosters)]
        for x in shuffled:
            random.Random(5).shuffle(x)
        self.assertEqual(first, transform(*shuffled, cfg()))


if __name__ == "__main__":
    unittest.main()
