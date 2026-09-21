"""Tests for the season model transform.

The transform is the one seam here: source rows and a Config in, the fitted
model out. Every test passes its own tuning (and builds its own data from a
formula it chose), so retuning the real numbers in config.py cannot break one,
and none reads a production coefficient.

Fetching, the sanity guards and artifact writing sit outside it and are covered
by the build's own guards instead.

Run with: python3 -m unittest discover scripts/qb_season_model
"""

import math
import random
import unittest

from transform import (
    AWARDS, LADDER_STEPS, SLOTS, Award, Config, Formula,
    LadderRung, Norm, OutputSpec, QbLine, RatedSeason, RealSeason, SeasonModel,
    TeamSeason, composite, earns, expected_depth, expected_metrics, fit,
    fit_awards, fit_distributions, fit_formulas, fit_ladder, fit_norms, fit_outputs,
    nearest_real_seasons, passer_rating, percentile_of, predict,
    qb_lines_from_weeks, quantile, real_seasons, score, season_metrics,
    team_seasons_from_games, values_of,
)

# ------------------------------------------------------------ source helpers --


def week(player="00-1", team="KC", season=2018, wk=1, position="QB", season_type="REG", **over):
    row = dict(
        player_id=player, position=position, season=str(season), week=str(wk),
        season_type=season_type, team=team, attempts="30", completions="20",
        passing_yards="250", passing_tds="2", passing_interceptions="1",
        carries="3", rushing_yards="12", rushing_tds="0",
    )
    row.update({k: str(v) for k, v in over.items()})
    return row


PFR = {"00-1": "PlayOn00", "00-2": "PlayTw00"}
CODES = {"KC": "kan", "LV": "rai", "OAK": "rai", "NE": "nwe"}


def game(season, kind, home, away, home_score, away_score, wk=1):
    return dict(season=str(season), game_type=kind, week=str(wk), home_team=home,
                away_team=away, home_score=str(home_score), away_score=str(away_score))


# ------------------------------------------------------------- passer rating --


class PasserRatingTest(unittest.TestCase):
    def test_a_perfect_line_is_158_3(self):
        # 20 for 25 for 375 yards, 3 TD, no interceptions hits every cap.
        self.assertAlmostEqual(passer_rating(20, 25, 375, 3, 0), 158.3, places=1)

    def test_a_worthless_line_is_zero(self):
        self.assertEqual(passer_rating(0, 20, 0, 0, 5), 0.0)

    def test_a_known_middle_line(self):
        # 300 of 500, 3,600 yards, 24 TD, 12 INT, worked by hand:
        # a=(0.6-0.3)*5=1.5  b=(7.2-3)*.25=1.05  c=.048*20=.96  d=2.375-.024*25=1.775
        self.assertAlmostEqual(passer_rating(300, 500, 3600, 24, 12),
                               (1.5 + 1.05 + 0.96 + 1.775) / 6 * 100, places=6)

    def test_no_attempts_is_zero_not_a_crash(self):
        self.assertEqual(passer_rating(0, 0, 0, 0, 0), 0.0)


# ---------------------------------------------------------------- qb lines --


class QbLinesTest(unittest.TestCase):
    def test_sums_a_quarterbacks_regular_season_for_one_team(self):
        rows = [week(wk=1), week(wk=2, attempts=40, completions=30, passing_yards=350,
                                 passing_tds=3, passing_interceptions=0, carries=5,
                                 rushing_yards=30, rushing_tds=1)]
        (line,) = qb_lines_from_weeks(rows, PFR, CODES)
        self.assertEqual(line, QbLine(
            franchise_code="kan", season=2018, player_id="PlayOn00", attempts=70,
            completions=50, pass_yards=600.0, pass_tds=5, interceptions=1,
            rush_yards=42.0, rush_tds=1))

    def test_ignores_the_postseason_and_other_positions(self):
        rows = [week(), week(season_type="POST", wk=19), week(player="00-2", position="RB")]
        (line,) = qb_lines_from_weeks(rows, PFR, CODES)
        self.assertEqual(line.attempts, 30)

    def test_a_player_who_never_threw_has_no_line(self):
        self.assertEqual(qb_lines_from_weeks([week(attempts=0, completions=0)], PFR, CODES), [])

    def test_blank_and_na_cells_count_as_zero(self):
        (line,) = qb_lines_from_weeks([week(rushing_tds="NA", rushing_yards="")], PFR, CODES)
        self.assertEqual((line.rush_tds, line.rush_yards), (0, 0.0))

    def test_a_quarterback_on_two_teams_is_two_lines(self):
        rows = [week(team="KC"), week(team="LV", wk=2)]
        lines = qb_lines_from_weeks(rows, PFR, CODES)
        self.assertEqual(sorted(l.franchise_code for l in lines), ["kan", "rai"])

    def test_a_player_with_no_pfr_id_is_left_out(self):
        # Only rated seasons are joined later, and a rated one always has an id.
        self.assertEqual(qb_lines_from_weeks([week(player="00-9")], PFR, CODES), [])

    def test_an_unknown_team_code_is_an_error(self):
        with self.assertRaises(ValueError):
            qb_lines_from_weeks([week(team="XXX")], PFR, CODES)


# ------------------------------------------------------------- team seasons --


class TeamSeasonsTest(unittest.TestCase):
    def by_team(self, rows):
        return {(t.franchise_code, t.season): t for t in rows}

    def test_counts_wins_losses_and_ties_from_the_regular_season(self):
        rows = [
            game(2018, "REG", "KC", "NE", 30, 20),
            game(2018, "REG", "NE", "KC", 17, 17, wk=2),
            game(2018, "REG", "KC", "NE", 10, 24, wk=3),
        ]
        teams = self.by_team(team_seasons_from_games(rows, CODES, 2018, 2018))
        self.assertEqual((teams[("kan", 2018)].wins, teams[("kan", 2018)].losses,
                          teams[("kan", 2018)].ties), (1, 1, 1))
        self.assertEqual((teams[("nwe", 2018)].wins, teams[("nwe", 2018)].losses,
                          teams[("nwe", 2018)].ties), (1, 1, 1))

    def test_a_team_out_of_the_playoffs_is_depth_zero(self):
        rows = [game(2018, "REG", "KC", "NE", 30, 20)]
        for t in team_seasons_from_games(rows, CODES, 2018, 2018):
            self.assertEqual(t.playoff_depth, 0)

    def test_depth_is_the_furthest_round_a_team_played(self):
        rows = [
            game(2018, "REG", "KC", "NE", 30, 20),
            game(2018, "WC", "NE", "KC", 20, 10, wk=19),     # KC out in the wild card
            game(2018, "DIV", "NE", "OAK", 10, 13, wk=20),   # NE out in the divisional
        ]
        teams = self.by_team(team_seasons_from_games(rows, CODES, 2018, 2018))
        self.assertEqual(teams[("kan", 2018)].playoff_depth, 1)
        self.assertEqual(teams[("nwe", 2018)].playoff_depth, 2)

    def test_a_bye_team_that_loses_its_first_game_lost_the_divisional_round(self):
        rows = [game(2018, "REG", "KC", "NE", 30, 20), game(2018, "DIV", "KC", "NE", 3, 10)]
        teams = self.by_team(team_seasons_from_games(rows, CODES, 2018, 2018))
        self.assertEqual(teams[("kan", 2018)].playoff_depth, 2)

    def test_depth_climbs_through_each_round_to_the_title(self):
        def depth_of(kind, home_score, away_score):
            rows = [game(2018, "REG", "KC", "NE", 1, 0),
                    game(2018, kind, "KC", "NE", home_score, away_score)]
            return self.by_team(team_seasons_from_games(rows, CODES, 2018, 2018))[("kan", 2018)].playoff_depth
        self.assertEqual(depth_of("WC", 1, 9), 1)
        self.assertEqual(depth_of("DIV", 1, 9), 2)
        self.assertEqual(depth_of("CON", 1, 9), 3)
        self.assertEqual(depth_of("SB", 1, 9), 4)   # lost the Super Bowl
        self.assertEqual(depth_of("SB", 9, 1), 5)   # won it

    def test_seasons_outside_the_range_and_unplayed_games_are_skipped(self):
        rows = [game(2005, "REG", "KC", "NE", 1, 0), game(2018, "REG", "KC", "NE", "", "")]
        self.assertEqual(team_seasons_from_games(rows, CODES, 2018, 2018), [])

    def test_two_nflverse_codes_for_one_franchise_are_one_team(self):
        # Oakland and Las Vegas are one franchise ('rai') across the range.
        rows = [game(2019, "REG", "OAK", "NE", 1, 0), game(2019, "REG", "LV", "NE", 1, 0, wk=2)]
        teams = self.by_team(team_seasons_from_games(rows, CODES, 2019, 2019))
        self.assertEqual(teams[("rai", 2019)].wins, 2)
        self.assertEqual(teams[("nwe", 2019)].losses, 2)


# ------------------------------------------------------------- real seasons --


def rated(player="PlayOn00", team="kan", season=2018, **over):
    row = dict(franchise_code=team, season=season, player_id=player, display_name=player,
               accuracy=80, arm_talent=70, mobility=60, iq=75, build=65, supporting_cast=55)
    row.update(over)
    return RatedSeason(**row)


def line(player="PlayOn00", team="kan", season=2018, **over):
    row = dict(franchise_code=team, season=season, player_id=player, attempts=500,
               completions=320, pass_yards=3800.0, pass_tds=28, interceptions=10,
               rush_yards=150.0, rush_tds=2)
    row.update(over)
    return QbLine(**row)


def team(code="kan", season=2018, wins=10, losses=6, ties=0, depth=2):
    return TeamSeason(code, season, wins, losses, ties, depth)


def cfg(**over):
    base = dict(
        season_games=17,
        outputs={"ypa": OutputSpec("identity", 0.0, 20.0, 0.5, "qb_line"),
                 "wins": OutputSpec("logit", 0.0, 17.0, 1.0, "team")},
        logit_margin=0.03,
        log_floor=0.005,
        residual_points=11,
        ladder_ridge=0.01,
        stat_line_weights={"pass_yards": 1.0, "rating": 1.0},
        team_success_weights={"wins": 1.0, "playoff_depth": 1.0},
        award_points={"mvp": 5.0, "opoy": 3.0, "all_pro": 3.0, "pro_bowl": 1.0, "sb_mvp": 3.0},
        score_weights={"stat_line": 0.5, "team_success": 0.3, "awards": 0.2},
        award_terms={a: {"pass_yards": 1.0, "wins": 1.0} for a in AWARDS},
        award_quantile={a: 0.25 for a in AWARDS},
        award_noise_scale={a: 0.5 for a in AWARDS},
        distribution_points=11,
    )
    base.update(over)
    return Config(**base)


class RealSeasonsTest(unittest.TestCase):
    def build(self, **kw):
        args = dict(rated=[rated()], lines=[line()], teams=[team()], awards=[])
        args.update(kw)
        return real_seasons(**args)

    def test_joins_a_rated_season_to_its_line_its_team_and_its_values(self):
        (r,) = self.build()
        self.assertEqual((r.franchise_code, r.season, r.player_id), ("kan", 2018, "PlayOn00"))
        self.assertEqual((r.accuracy, r.arm_talent, r.mobility, r.iq, r.build, r.supporting_cast),
                         (80, 70, 60, 75, 65, 55))
        self.assertEqual((r.attempts, r.pass_yards, r.pass_tds, r.wins, r.losses, r.playoff_depth),
                         (500, 3800.0, 28, 10, 6, 2))

    def test_a_rated_season_with_no_line_is_an_error_not_a_dropped_row(self):
        with self.assertRaisesRegex(ValueError, "PlayOn00"):
            self.build(lines=[])

    def test_a_rated_season_with_no_team_result_is_an_error(self):
        with self.assertRaisesRegex(ValueError, "kan"):
            self.build(teams=[])

    def test_an_award_lands_on_the_winners_biggest_season_that_year(self):
        # Traded midseason: two rows for the player-season, the award goes to the
        # one with the bigger workload, so it is counted once.
        rows = self.build(
            rated=[rated(team="kan"), rated(team="nwe")],
            lines=[line(team="kan", attempts=100), line(team="nwe", attempts=400)],
            teams=[team("kan"), team("nwe")],
            awards=[Award(2018, "mvp", "PlayOn00"), Award(2018, "pro_bowl", "PlayOn00")],
        )
        by_team = {r.franchise_code: r for r in rows}
        self.assertEqual(by_team["nwe"].awards, frozenset({"mvp", "pro_bowl"}))
        self.assertEqual(by_team["kan"].awards, frozenset())

    def test_an_award_naming_nobody_in_the_ratings_is_an_error(self):
        with self.assertRaisesRegex(ValueError, "Ghost00"):
            self.build(awards=[Award(2018, "mvp", "Ghost00")])

    def test_an_unknown_award_is_an_error(self):
        with self.assertRaisesRegex(ValueError, "heisman"):
            self.build(awards=[Award(2018, "heisman", "PlayOn00")])

    def test_output_order_is_by_season_team_and_player(self):
        rows = self.build(
            rated=[rated(season=2019), rated(season=2018, player="B"), rated(season=2018, player="A")],
            lines=[line(season=2019), line(season=2018, player="B"), line(season=2018, player="A")],
            teams=[team(season=2019), team(season=2018)],
        )
        self.assertEqual([(r.season, r.player_id) for r in rows],
                         [(2018, "A"), (2018, "B"), (2019, "PlayOn00")])


# ------------------------------------------------------------- the fit itself --


def values_grid(n, seed=1):
    """n distinct-ish six-value builds, the way real ones scatter across 25-99."""
    rng = random.Random(seed)
    return [tuple(rng.randint(25, 99) for _ in SLOTS) for _ in range(n)]


def season(i, values, *, ypa=7.0, wins=8, attempts=500, depth=0, awards=(), games=17, **over):
    """A synthetic real season whose stat line is whatever the test chose."""
    a, arm, mob, iq, bld, cast = values
    row = dict(
        franchise_code="kan", season=2000 + i % 20, player_id=f"P{i:04d}", display_name=f"P{i}",
        accuracy=a, arm_talent=arm, mobility=mob, iq=iq, build=bld, supporting_cast=cast,
        attempts=attempts, completions=int(attempts * 0.62), pass_yards=attempts * ypa,
        pass_tds=int(attempts * 0.045), interceptions=int(attempts * 0.025),
        rush_yards=100.0, rush_tds=1, wins=wins, losses=games - wins, ties=0,
        playoff_depth=depth, awards=frozenset(awards),
    )
    row.update(over)
    return RealSeason(**row)


def linear_ypa(values):
    a, arm, mob, iq, bld, cast = values
    return 4.0 + 0.03 * a + 0.02 * arm + 0.005 * mob + 0.01 * iq + 0.0 * bld + 0.004 * cast


def ypa_only(**over):
    return cfg(outputs={"ypa": OutputSpec("identity", 0.0, 20.0, 0.3, "qb_line")}, **over)


class FitOutputsTest(unittest.TestCase):
    def synthetic(self, n=60):
        return [season(i, v, ypa=linear_ypa(v), wins=8) for i, v in enumerate(values_grid(n))]

    def test_recovers_the_formula_the_data_was_made_from(self):
        outputs = fit_outputs(self.synthetic(), ypa_only())
        (out,) = outputs
        self.assertEqual(out.name, "ypa")
        self.assertAlmostEqual(out.intercept, 4.0, places=6)
        want = dict(accuracy=0.03, arm_talent=0.02, mobility=0.005, iq=0.01, build=0.0,
                    supporting_cast=0.004)
        for slot, coefficient in zip(SLOTS, out.coefficients):
            self.assertAlmostEqual(coefficient, want[slot], places=6, msg=slot)
        self.assertAlmostEqual(out.residual_sd, 0.0, places=6)
        self.assertAlmostEqual(out.r_squared, 1.0, places=6)

    def correlated(self, n=80):
        """Accuracy and IQ move together (IQ is Accuracy plus a small wobble); only
        Accuracy actually drives the outcome."""
        out = []
        for i in range(n):
            acc = 25 + (i * 7) % 70
            wobble = (i % 5) - 2
            v = (acc, 25 + (i * 11) % 70, 25 + (i * 13) % 70, min(99, acc + wobble),
                 25 + (i * 17) % 70, 25 + (i * 19) % 70)
            out.append(season(i, v, ypa=4.0 + 0.05 * acc))
        return out

    def test_a_ridge_of_zero_is_ordinary_least_squares(self):
        seasons = self.correlated()
        (plain,) = fit_outputs(seasons, ypa_only())
        (zero,) = fit_outputs(seasons, cfg(outputs={"ypa": OutputSpec("identity", 0.0, 20.0, 0.3, "qb_line", 0.0)}))
        self.assertEqual(plain.coefficients, zero.coefficients)

    def test_a_ridge_shares_credit_between_values_that_move_together(self):
        seasons = self.correlated()
        (plain,) = fit_outputs(seasons, ypa_only())
        (ridged,) = fit_outputs(seasons, cfg(outputs={"ypa": OutputSpec("identity", 0.0, 20.0, 0.3, "qb_line", 0.05)}))
        acc, iq = SLOTS.index("accuracy"), SLOTS.index("iq")
        # Least squares finds the true one (Accuracy) and gives IQ nothing; a ridge
        # gives IQ a real share and Accuracy less than all of it.
        self.assertAlmostEqual(plain.coefficients[iq], 0.0, places=4)
        self.assertAlmostEqual(plain.coefficients[acc], 0.05, places=4)
        self.assertGreater(ridged.coefficients[iq], 0.01)
        self.assertLess(ridged.coefficients[acc], 0.04)
        # ...and together they still carry about what the one carried alone.
        self.assertAlmostEqual(ridged.coefficients[acc] + ridged.coefficients[iq], 0.05, delta=0.005)

    def shared(self, n=90):
        """Supporting Cast rises with Accuracy, and both drive the outcome."""
        out = []
        for i in range(n):
            acc = 25 + (i * 7) % 70
            cast = min(99, max(25, acc + ((i * 5) % 31) - 15))
            v = (acc, 25 + (i * 11) % 70, 25 + (i * 13) % 70, 25 + (i * 17) % 70,
                 25 + (i * 19) % 70, cast)
            out.append(season(i, v, ypa=4.0 + 0.03 * acc + 0.03 * cast))
        return out

    def trimmed(self, factor):
        spec = OutputSpec("identity", 0.0, 20.0, 0.3, "qb_line", trim=(("supporting_cast", factor),))
        (out,) = fit_outputs(self.shared(), cfg(outputs={"ypa": spec}))
        return out

    def test_a_trim_of_one_changes_nothing(self):
        (plain,) = fit_outputs(self.shared(), ypa_only())
        one = self.trimmed(1.0)
        for a, b in zip(plain.coefficients, one.coefficients):
            self.assertAlmostEqual(a, b, places=9)

    def test_a_trim_holds_the_value_at_its_factor_and_the_others_pick_up_the_rest(self):
        (plain,) = fit_outputs(self.shared(), ypa_only())
        half = self.trimmed(0.5)
        cast, acc = SLOTS.index("supporting_cast"), SLOTS.index("accuracy")
        self.assertAlmostEqual(half.coefficients[cast], plain.coefficients[cast] * 0.5, places=9)
        # Accuracy moves with the cast, so it absorbs part of what was trimmed.
        self.assertGreater(half.coefficients[acc], plain.coefficients[acc] + 0.005)

    def test_a_trimmed_fit_still_passes_through_the_mean_of_the_data(self):
        seasons = self.shared()
        out = self.trimmed(0.6)
        n = len(seasons)
        mean_values = [sum(values_of(s)[j] for s in seasons) / n for j in range(6)]
        mean_y = sum(s.pass_yards / s.attempts for s in seasons) / n
        got = out.intercept + sum(c * m for c, m in zip(out.coefficients, mean_values))
        self.assertAlmostEqual(got, mean_y, places=6)

    def test_a_ridge_leaves_the_intercept_unpenalised(self):
        # The fit still passes through the mean of the data.
        seasons = self.correlated()
        (out,) = fit_outputs(seasons, cfg(outputs={"ypa": OutputSpec("identity", 0.0, 20.0, 0.3, "qb_line", 0.2)}))
        n = len(seasons)
        mean_values = [sum(values_of(s)[j] for s in seasons) / n for j in range(6)]
        mean_y = sum(s.pass_yards / s.attempts for s in seasons) / n
        got = out.intercept + sum(c * m for c, m in zip(out.coefficients, mean_values))
        self.assertAlmostEqual(got, mean_y, places=6)

    def test_r_squared_says_how_much_of_the_spread_the_formula_explains(self):
        rng = random.Random(3)
        seasons = [season(i, v, ypa=linear_ypa(v) + rng.gauss(0, 1.0))
                   for i, v in enumerate(values_grid(300))]
        (out,) = fit_outputs(seasons, ypa_only())
        # The formula's own spread is 0.02*99-ish across builds (sd ~0.4) against
        # noise of sd 1: it explains some, far from all.
        self.assertGreater(out.r_squared, 0.02)
        self.assertLess(out.r_squared, 0.4)

    def test_an_output_that_never_varies_explains_nothing_and_does_not_crash(self):
        seasons = [season(i, v, ypa=7.0) for i, v in enumerate(values_grid(30))]
        (out,) = fit_outputs(seasons, ypa_only())
        self.assertEqual(out.r_squared, 0.0)

    def test_extrapolates_beyond_every_real_season(self):
        # The point of a fitted formula and not a lookup: a perfect build is
        # better than anything the sample ever held.
        seasons = self.synthetic()
        outputs = fit_outputs(seasons, ypa_only())
        best_real = max(s.pass_yards / s.attempts for s in seasons)
        perfect = predict(outputs, (99,) * 6)["ypa"]
        self.assertGreater(perfect, best_real + 0.05)
        self.assertGreater(predict(outputs, (150,) * 6)["ypa"], perfect)

    def test_a_better_build_never_predicts_a_worse_season_when_every_effect_is_positive(self):
        outputs = fit_outputs(self.synthetic(), ypa_only())
        low = predict(outputs, (40, 40, 40, 40, 40, 40))["ypa"]
        high = predict(outputs, (80, 80, 80, 80, 80, 80))["ypa"]
        self.assertGreater(high, low)

    def test_an_identity_output_is_held_inside_its_bounds(self):
        outputs = fit_outputs(self.synthetic(), cfg(outputs={
            "ypa": OutputSpec("identity", 0.0, 9.0, 0.3, "qb_line")}))
        self.assertEqual(predict(outputs, (999,) * 6)["ypa"], 9.0)
        self.assertEqual(predict(outputs, (-999,) * 6)["ypa"], 0.0)

    def test_a_log_output_can_never_go_negative(self):
        seasons = [season(i, v, attempts=int(300 + 3 * v[0] + 2 * v[1])) for i, v in enumerate(values_grid(60))]
        outputs = fit_outputs(seasons, cfg(outputs={"attempts": OutputSpec("log", 0.0, 1e9, 0.3, "qb_line")}))
        self.assertGreater(predict(outputs, (-500,) * 6)["attempts"], 0.0)
        self.assertGreater(predict(outputs, (99,) * 6)["attempts"], max(s.attempts for s in seasons))

    def test_a_zero_in_a_log_output_is_floored_and_not_an_outlier_that_ruins_the_fit(self):
        seasons = [season(i, v, pass_tds=int(500 * (0.03 + 0.0002 * v[0])))
                   for i, v in enumerate(values_grid(80))]
        seasons[0] = seasons[0]._replace(pass_tds=0)     # a season that really threw none
        outputs = fit_outputs(seasons, cfg(
            outputs={"td_rate": OutputSpec("log", 0.0, 0.12, 0.3, "qb_line")}, log_floor=0.005))
        # Floored at 0.5%, not sent to log(0): the worst miss is a few units, not 17.
        self.assertGreater(outputs[0].residuals[0][1], -3.0)

    def test_a_logit_output_can_never_leave_its_range_however_far_it_extrapolates(self):
        # Wins driven by the cast: rises with it, but a 17-game season tops out.
        seasons = [season(i, v, wins=round(17 / (1 + math.exp(-(v[5] - 60) / 15))))
                   for i, v in enumerate(values_grid(80, seed=3))]
        outputs = fit_outputs(seasons, cfg(outputs={"wins": OutputSpec("logit", 0.0, 17.0, 1.0, "team")}))
        top, bottom = predict(outputs, (999,) * 6)["wins"], predict(outputs, (-999,) * 6)["wins"]
        self.assertLessEqual(top, 17.0)
        self.assertGreaterEqual(bottom, 0.0)
        self.assertGreater(predict(outputs, (50, 50, 50, 50, 50, 95))["wins"],
                           predict(outputs, (50, 50, 50, 50, 50, 30))["wins"])

    def test_a_draw_moves_an_output_by_its_noise_scale_times_the_real_residual_at_thatquantile(self):
        outputs = fit_outputs(self.noisy(), cfg(
            outputs={"ypa": OutputSpec("identity", 0.0, 20.0, 0.3, "qb_line")}, residual_points=21))
        (out,) = outputs
        base = predict(outputs, (60,) * 6)["ypa"]
        top = predict(outputs, (60,) * 6, {"ypa": 1.0})["ypa"]
        bottom = predict(outputs, (60,) * 6, {"ypa": 0.0})["ypa"]
        self.assertAlmostEqual(top - base, 0.3 * out.residuals[-1][1])
        self.assertAlmostEqual(bottom - base, 0.3 * out.residuals[0][1])
        # Between two table points it interpolates: u = 0.025 is halfway from p=0 to p=0.05.
        mid = predict(outputs, (60,) * 6, {"ypa": 0.025})["ypa"]
        self.assertAlmostEqual(mid - base, 0.3 * (out.residuals[0][1] + out.residuals[1][1]) / 2)

    def test_no_draw_is_the_expected_season_and_a_draw_never_leaves_the_bounds(self):
        seasons = [season(i, v, wins=max(0, min(17, round(v[5] / 6)))) for i, v in enumerate(values_grid(80, seed=3))]
        outputs = fit_outputs(seasons, cfg(outputs={"wins": OutputSpec("logit", 0.0, 17.0, 1.0, "team")}))
        self.assertEqual(predict(outputs, (60,) * 6), predict(outputs, (60,) * 6, {}))
        for u in (0.0, 0.5, 1.0):
            self.assertTrue(0.0 <= predict(outputs, (999,) * 6, {"wins": u})["wins"] <= 17.0)
            self.assertTrue(0.0 <= predict(outputs, (-999,) * 6, {"wins": u})["wins"] <= 17.0)

    def noisy(self):
        rng = random.Random(9)
        return [season(i, v, ypa=linear_ypa(v) + rng.uniform(-0.6, 0.6))
                for i, v in enumerate(values_grid(150))]

    def test_a_sixteen_game_season_is_a_full_seventeen_game_one(self):
        seasons = self.synthetic()
        sixteen = [s._replace(wins=16, losses=0) for s in seasons]
        outputs = fit_outputs(sixteen, cfg(outputs={"wins": OutputSpec("logit", 0.0, 17.0, 1.0, "team")}))
        # A 16-0 team wins its whole schedule: near the top of 17, not 16.
        self.assertGreater(predict(outputs, (60,) * 6)["wins"], 16.0)

    def test_residualquantiles_span_the_real_spread_and_are_ordered(self):
        rng = random.Random(7)
        seasons = [season(i, v, ypa=linear_ypa(v) + rng.uniform(-0.5, 0.5))
                   for i, v in enumerate(values_grid(120))]
        outputs = fit_outputs(seasons, ypa_only(residual_points=11))
        (out,) = outputs
        ps = [p for p, _ in out.residuals]
        rs = [r for _, r in out.residuals]
        self.assertEqual(len(rs), 11)
        self.assertEqual((ps[0], ps[-1]), (0.0, 1.0))
        self.assertEqual(rs, sorted(rs))
        # Bounded: the extremes are the real extremes (the noise was +/-0.5, and
        # fitting six terms moves a residual only a little), not a fitted tail.
        self.assertLess(rs[-1], 0.7)
        self.assertGreater(rs[0], -0.7)
        self.assertGreater(rs[-1], 0.35)
        self.assertLess(rs[0], -0.35)
        self.assertAlmostEqual(rs[5], 0.0, delta=0.1)
        # Uniform noise on +/-0.5 has an sd of 0.5/sqrt(3).
        self.assertAlmostEqual(out.residual_sd, 0.5 / math.sqrt(3), delta=0.05)

    def test_each_output_keeps_its_own_noise_scale_and_group(self):
        seasons = self.synthetic()
        outputs = fit_outputs(seasons, cfg(outputs={
            "ypa": OutputSpec("identity", 0.0, 20.0, 0.25, "qb_line"),
            "wins": OutputSpec("logit", 0.0, 17.0, 1.0, "team"),
        }))
        by_name = {o.name: o for o in outputs}
        self.assertEqual((by_name["ypa"].spec.noise_scale, by_name["ypa"].spec.group), (0.25, "qb_line"))
        self.assertEqual((by_name["wins"].spec.noise_scale, by_name["wins"].spec.group), (1.0, "team"))

    def test_residual_spread_is_recorded_per_output(self):
        rng = random.Random(11)
        seasons = [season(i, v, ypa=linear_ypa(v) + rng.gauss(0, 0.1),
                          wins=max(0, min(17, round(8 + (v[5] - 60) / 8 + rng.gauss(0, 3)))))
                   for i, v in enumerate(values_grid(150, seed=5))]
        outputs = fit_outputs(seasons, cfg())
        by_name = {o.name: o for o in outputs}
        self.assertEqual(sorted(by_name), ["wins", "ypa"])
        self.assertLess(by_name["ypa"].residual_sd, 0.2)
        self.assertGreater(by_name["wins"].residual_sd, 0.3)   # in logit units: far noisier

    def test_an_unknown_output_name_is_an_error(self):
        with self.assertRaisesRegex(ValueError, "sacks"):
            fit_outputs(self.synthetic(), cfg(outputs={"sacks": OutputSpec("identity", 0, 9, 1, "qb_line")}))

    def test_too_few_seasons_to_fit_seven_terms_is_an_error(self):
        with self.assertRaisesRegex(ValueError, "seasons"):
            fit_outputs(self.synthetic(n=7), ypa_only())

    def test_input_order_does_not_change_the_fit(self):
        seasons = self.synthetic()
        shuffled = list(seasons)
        random.Random(0).shuffle(shuffled)
        self.assertEqual(fit_outputs(seasons, ypa_only()), fit_outputs(shuffled, ypa_only()))


# ----------------------------------------------------------- playoff ladder --


def team_at(wins, depth, i=0, games=17):
    return TeamSeason(f"t{i % 32:02d}", 2000 + i // 32, wins, games - wins, 0, depth)


def league_from(model_p, n=6000, seed=4):
    """A league whose playoff results really follow the given per-rung logistics."""
    rng = random.Random(seed)
    teams = []
    for i in range(n):
        wins = rng.randint(0, 17)
        depth = 0
        for a, b in model_p:
            if rng.random() < 1 / (1 + math.exp(-(a + b * wins))):
                depth += 1
            else:
                break
        teams.append(team_at(wins, depth, i))
    return teams


class LadderTest(unittest.TestCase):
    TRUE = [(-9.0, 1.0), (-2.0, 0.3), (-1.5, 0.25), (-1.0, 0.2), (-0.5, 0.15)]

    def test_has_one_rung_per_step_in_order(self):
        ladder = fit_ladder(league_from(self.TRUE), cfg(ladder_ridge=1e-9))
        self.assertEqual([r.step for r in ladder], list(LADDER_STEPS))

    def test_recovers_the_chance_of_the_early_rungs_from_the_results(self):
        ladder = fit_ladder(league_from(self.TRUE), cfg(ladder_ridge=1e-9))
        for rung, (a, b) in zip(ladder[:2], self.TRUE[:2]):
            self.assertAlmostEqual(rung.slope, b, delta=0.1, msg=rung.step)
            self.assertAlmostEqual(rung.intercept, a, delta=0.6, msg=rung.step)

    def test_more_wins_is_never_a_worse_chance_at_any_rung(self):
        ladder = fit_ladder(league_from(self.TRUE), cfg(ladder_ridge=1e-9))
        self.assertTrue(all(r.slope >= 0 for r in ladder))

    def test_a_rung_teams_never_missed_still_fits_a_finite_answer(self):
        # Every team with 12+ wins made it and every team below did not: perfectly
        # separable, which an unpenalised logistic would answer with infinity.
        teams = [team_at(w, 1 if w >= 12 else 0, i) for i, w in enumerate(list(range(18)) * 8)]
        teams += [team_at(w, 4 + (w > 14), 1000 + i) for i, w in enumerate(range(12, 18))]
        rung = fit_ladder(teams, cfg(ladder_ridge=0.05))[0]
        self.assertTrue(math.isfinite(rung.slope) and math.isfinite(rung.intercept))
        self.assertGreater(rung.slope, 0)

    def test_a_slope_the_data_gives_the_wrong_sign_is_held_at_zero(self):
        # Later rungs of a tiny sample can drift downhill by chance; more wins
        # must never be worse, so the fit holds them flat instead.
        teams = [team_at(w, 0 if w > 8 else 1, i) for i, w in enumerate(list(range(18)) * 6)]
        teams += [team_at(w, 2, 900 + i) for i, w in enumerate(range(2, 8))]
        teams += [team_at(9, 4, 950), team_at(10, 5, 951)]
        ladder = fit_ladder(teams, cfg(ladder_ridge=0.01))
        self.assertEqual(ladder[0].slope, 0.0)

    def test_a_rung_no_team_ever_reached_is_an_error(self):
        with self.assertRaisesRegex(ValueError, "win_super_bowl"):
            fit_ladder([team_at(w, min(w // 4, 3), i) for i, w in enumerate(list(range(18)) * 8)],
                       cfg())

    def test_expected_depth_is_the_sum_of_surviving_each_rung(self):
        coin = tuple(LadderRung(step, 0.0, 0.0) for step in LADDER_STEPS)
        # Every rung a coin flip: 1/2 + 1/4 + 1/8 + 1/16 + 1/32.
        self.assertAlmostEqual(expected_depth(coin, 10), 0.96875)


# ------------------------------------------------------------ metrics, norms --


def hand_seasons():
    """Three seasons with round numbers: 3,000 / 4,000 / 5,000 yards."""
    return [
        season(0, (50,) * 6, ypa=6.0, wins=6, depth=0),                    # 3000 yards
        season(1, (60,) * 6, ypa=8.0, wins=10, depth=2, awards=["pro_bowl"]),   # 4000
        season(2, (70,) * 6, ypa=10.0, wins=14, depth=5, awards=["mvp", "pro_bowl", "sb_mvp"]),  # 5000
    ]


class MetricsTest(unittest.TestCase):
    def test_a_seasons_metrics_are_per_full_season(self):
        s = season(0, (50,) * 6, ypa=7.6, wins=8, games=16, attempts=500)
        m = season_metrics(s, cfg(season_games=17))
        self.assertAlmostEqual(m["pass_yards"], 500 * 7.6 * 17 / 16)
        self.assertAlmostEqual(m["wins"], 8 * 17 / 16)
        self.assertAlmostEqual(m["rating"], passer_rating(s.completions, 500, 3800, s.pass_tds, s.interceptions))
        self.assertEqual(m["playoff_depth"], 0)

    def test_norms_are_the_mean_and_spread_of_the_real_seasons(self):
        norms = {n.metric: n for n in fit_norms(hand_seasons(), cfg())}
        self.assertAlmostEqual(norms["pass_yards"].mean, 4000.0)
        self.assertAlmostEqual(norms["pass_yards"].sd, math.sqrt(2 / 3) * 1000)

    def test_a_metric_that_never_varies_contributes_nothing_rather_than_dividing_by_zero(self):
        norms = {n.metric: n for n in fit_norms(hand_seasons(), cfg())}
        self.assertEqual(norms["rush_yards"].sd, 1.0)   # every season ran for 100


def bare_model(**over):
    """A model with only what arithmetic on composites needs, made by hand."""
    base = dict(
        outputs=(), ladder=(),
        norms=(Norm("pass_yards", 4000.0, 1000.0), Norm("wins", 9.0, 3.0), Norm("playoff_depth", 1.0, 1.0)),
        formulas=(
            Formula("stat_line", "pass_yards", 1.0),
            Formula("team_success", "wins", 2.0), Formula("team_success", "playoff_depth", 1.0),
            Formula("awards", "mvp", 5.0), Formula("awards", "pro_bowl", 1.0),
            Formula("score", "stat_line", 5.0), Formula("score", "team_success", 3.0),
            Formula("score", "awards", 2.0),
        ),
        awards=(), distributions={}, real=(),
    )
    base.update(over)
    return SeasonModel(**base)


class CompositeTest(unittest.TestCase):
    def test_a_composite_is_the_weighted_sum_of_z_scores(self):
        m = {"pass_yards": 5000.0, "wins": 12.0, "playoff_depth": 3.0}
        self.assertAlmostEqual(composite(bare_model(), "stat_line", m), 1.0)
        # wins: (12-9)/3 = 1 at weight 2, depth: (3-1)/1 = 2 at weight 1
        self.assertAlmostEqual(composite(bare_model(), "team_success", m), 2 * 1 + 1 * 2)

    def test_awards_are_points_not_z_scores(self):
        m = {}
        self.assertEqual(composite(bare_model(), "awards", m, {"mvp", "pro_bowl"}), 6.0)
        self.assertEqual(composite(bare_model(), "awards", m, set()), 0.0)

    def test_percentile_is_the_share_of_real_seasons_strictly_below(self):
        table = tuple((i / 4, v) for i, v in enumerate([0.0, 0.0, 0.0, 1.0, 2.0]))
        self.assertEqual(percentile_of(table, -1.0), 0.0)
        self.assertEqual(percentile_of(table, 5.0), 1.0)          # beyond every real season
        # "Better than X% of real seasons": a tie is not better, so a season with no
        # awards, like most real ones, is better than none of them.
        self.assertEqual(percentile_of(table, 0.0), 0.0)
        self.assertAlmostEqual(percentile_of(table, 1.0), 3 / 5)
        self.assertAlmostEqual(percentile_of(table, 2.0), 4 / 5)

    def test_the_score_mixes_the_three_percentiles_by_weight_and_tops_out_at_100(self):
        table = tuple((i / 4, float(i + 1)) for i in range(5))
        model = bare_model(distributions={"stat_line": table, "team_success": table, "awards": table})
        # Off every table's top: 100 whatever the weights add up to.
        top = {"pass_yards": 1e9, "wins": 1e9, "playoff_depth": 1e9}
        self.assertEqual(score(model, top, {"mvp", "pro_bowl"}), 100.0)
        # Below every table's floor: 0.
        floor = {"pass_yards": -1e9, "wins": -1e9, "playoff_depth": -1e9}
        self.assertEqual(score(model, floor, set()), 0.0)

    def test_the_score_weights_decide_how_much_each_component_counts(self):
        table = tuple((i / 4, float(i + 1)) for i in range(5))
        model = bare_model(distributions={"stat_line": table, "team_success": table, "awards": table})
        # Best possible stat line, nothing else: only the 5 of (5+3+2) counts.
        m = {"pass_yards": 1e9, "wins": -1e9, "playoff_depth": -1e9}
        self.assertAlmostEqual(score(model, m, set()), 50.0)


class QuantileTest(unittest.TestCase):
    def test_interpolating_between_equal_neighbours_returns_exactly_that_value(self):
        # -1.4695858455634698 * (1 - f) + -1.4695858455634698 * f is a hair off it
        # for some f, which put a step backwards in a table of tied seasons.
        a = -1.4695858455634698
        values = [a] * 15 + [a + 2.0] * 5
        table = [quantile(values, i / 100) for i in range(101)]
        self.assertEqual(table, sorted(table))
        self.assertTrue(all(v == a for v in table if v <= a + 1e-9))

    def test_the_ends_are_the_extremes_and_the_middle_interpolates(self):
        self.assertEqual(quantile([1.0, 2.0, 4.0], 0.0), 1.0)
        self.assertEqual(quantile([1.0, 2.0, 4.0], 1.0), 4.0)
        self.assertEqual(quantile([1.0, 2.0, 4.0], 0.75), 3.0)
        self.assertEqual(quantile([5.0], 0.3), 5.0)


class DistributionTest(unittest.TestCase):
    def test_each_component_tabulates_the_real_seasons_composites(self):
        seasons = hand_seasons()
        config = cfg(stat_line_weights={"pass_yards": 1.0}, team_success_weights={"wins": 1.0},
                     distribution_points=3)
        model = bare_model(norms=fit_norms(seasons, config))
        dist = fit_distributions(seasons, model.norms, model.formulas, config)
        stat = [v for _, v in dist["stat_line"]]
        # min, median, max of the composites of 3,000 / 4,000 / 5,000 yards.
        self.assertAlmostEqual(stat[0], -math.sqrt(1.5))
        self.assertAlmostEqual(stat[1], 0.0)
        self.assertAlmostEqual(stat[2], math.sqrt(1.5))
        self.assertEqual([p for p, _ in dist["awards"]], [0.0, 0.5, 1.0])


# ------------------------------------------------------------ award thresholds --


class AwardTest(unittest.TestCase):
    def setup(self, quantile):
        seasons = [
            season(0, (50,) * 6, ypa=6.0, wins=6),                                     # 3000 yds
            season(1, (60,) * 6, ypa=8.0, wins=10, awards=["mvp"]),                    # 4000
            season(2, (70,) * 6, ypa=9.0, wins=12, awards=["mvp"]),                    # 4500
            season(3, (80,) * 6, ypa=10.0, wins=14, awards=["mvp"]),                   # 5000
        ] + [season(10 + k, (60,) * 6, ypa=8.0, wins=9, awards=[a]) for k, a in
             enumerate(a for a in AWARDS if a != "mvp")]
        config = cfg(award_quantile={a: quantile for a in AWARDS})
        norms = fit_norms(seasons, config)
        return seasons, norms, config

    def score_of(self, s, norms):
        n = {x.metric: x for x in norms}
        m = season_metrics(s, cfg())
        return sum((m[k] - n[k].mean) / n[k].sd for k in ("pass_yards", "wins"))

    def test_the_threshold_sits_at_the_configuredquantile_of_the_real_winners(self):
        for quantile, pick in ((0.0, 1), (0.5, 2), (1.0, 3)):
            seasons, norms, config = self.setup(quantile)
            (mvp,) = [a for a in fit_awards(seasons, norms, config) if a.award == "mvp"]
            self.assertAlmostEqual(mvp.threshold, self.score_of(seasons[pick], norms), msg=str(quantile))

    def test_the_spread_is_that_of_the_winners_and_the_count_is_recorded(self):
        seasons, norms, config = self.setup(0.25)
        (mvp,) = [a for a in fit_awards(seasons, norms, config) if a.award == "mvp"]
        scores = [self.score_of(seasons[i], norms) for i in (1, 2, 3)]
        mean = sum(scores) / 3
        self.assertAlmostEqual(mvp.spread, math.sqrt(sum((x - mean) ** 2 for x in scores) / 3))
        self.assertEqual(mvp.winners, 3)
        self.assertEqual(mvp.noise_scale, 0.5)

    def test_every_award_gets_a_threshold_in_award_order(self):
        seasons, norms, config = self.setup(0.25)
        self.assertEqual([a.award for a in fit_awards(seasons, norms, config)], list(AWARDS))

    def test_an_award_no_real_season_won_is_an_error(self):
        seasons, norms, config = self.setup(0.25)
        without = [s._replace(awards=s.awards - {"opoy"}) for s in seasons]
        with self.assertRaisesRegex(ValueError, "opoy"):
            fit_awards(without, norms, config)

    def test_an_award_missing_from_the_tuning_is_an_error(self):
        seasons, norms, config = self.setup(0.25)
        with self.assertRaisesRegex(ValueError, "mvp"):
            fit_awards(seasons, norms, config._replace(award_terms={}))

    def test_a_season_earns_an_award_at_or_above_its_threshold(self):
        seasons, norms, config = self.setup(0.0)
        awards = fit_awards(seasons, norms, config)
        model = bare_model(norms=norms, awards=awards, formulas=fit_formulas(config))
        weakest_winner = season_metrics(seasons[1], cfg())
        self.assertTrue(earns(model, "mvp", weakest_winner))
        self.assertFalse(earns(model, "mvp", season_metrics(seasons[0], cfg())))

    def test_the_threshold_records_the_award_it_requires(self):
        seasons, norms, config = self.setup(0.0)
        config = config._replace(award_requires={"mvp": "all_pro", "opoy": "pro_bowl"})
        found = {a.award: a.requires for a in fit_awards(seasons, norms, config)}
        self.assertEqual(found, {"mvp": "all_pro", "opoy": "pro_bowl", "all_pro": "",
                                 "pro_bowl": "", "sb_mvp": ""})

    def test_without_a_requirement_no_award_requires_another(self):
        seasons, norms, config = self.setup(0.0)
        self.assertEqual({a.requires for a in fit_awards(seasons, norms, config)}, {""})

    def test_a_season_that_misses_the_required_award_cannot_take_the_one_that_needs_it(self):
        seasons, norms, config = self.setup(0.0)
        strong = season_metrics(seasons[3], cfg())
        free = bare_model(norms=norms, awards=fit_awards(seasons, norms, config),
                          formulas=fit_formulas(config))
        self.assertTrue(earns(free, "mvp", strong))
        needy = fit_awards(seasons, norms, config._replace(award_requires={"mvp": "pro_bowl"}))
        # The season clears MVP's own threshold; it only misses the Pro Bowl's, moved out of reach.
        needy = tuple(a._replace(threshold=1e9) if a.award == "pro_bowl" else a for a in needy)
        model = bare_model(norms=norms, awards=needy, formulas=fit_formulas(config))
        self.assertTrue(earns(model, "pro_bowl", strong) is False)
        self.assertFalse(earns(model, "mvp", strong))

    def test_a_requirement_the_season_meets_changes_nothing(self):
        seasons, norms, config = self.setup(0.0)
        needy = fit_awards(seasons, norms, config._replace(award_requires={"mvp": "pro_bowl"}))
        model = bare_model(norms=norms, awards=needy, formulas=fit_formulas(config))
        self.assertTrue(earns(model, "mvp", season_metrics(seasons[3], cfg())))

    def test_a_requirement_naming_no_award_or_itself_is_an_error(self):
        seasons, norms, config = self.setup(0.25)
        for bad in ({"mvp": "heisman"}, {"mvp": "mvp"}, {"heisman": "mvp"}):
            with self.assertRaisesRegex(ValueError, "award_requires"):
                fit_awards(seasons, norms, config._replace(award_requires=bad))


# -------------------------------------------------------- nearest real season --


class NearestTest(unittest.TestCase):
    def test_the_closest_real_season_on_the_six_values_comes_first(self):
        real = tuple(sorted([season(0, (50,) * 6), season(1, (70,) * 6), season(2, (95,) * 6)],
                            key=lambda s: s.player_id))
        model = bare_model(real=real)
        (best,) = nearest_real_seasons(model, (72, 68, 70, 71, 69, 70), 1)
        self.assertEqual(best.player_id, "P0001")
        order = [s.player_id for s in nearest_real_seasons(model, (62,) * 6, 3)]
        self.assertEqual(order, ["P0001", "P0000", "P0002"])

    def test_a_tie_is_broken_by_the_real_seasons_own_order(self):
        real = (season(0, (50,) * 6), season(1, (50,) * 6))
        self.assertEqual(nearest_real_seasons(bare_model(real=real), (50,) * 6, 1)[0].player_id, "P0000")


# ------------------------------------------------------------ the whole fit --


def full_cfg(**over):
    outputs = {
        "attempts": OutputSpec("log", 0.0, 1e9, 0.2, "qb_line"),
        "comp_pct": OutputSpec("logit", 0.4, 0.8, 0.2, "qb_line"),
        "ypa": OutputSpec("identity", 3.0, 12.0, 0.2, "qb_line"),
        "td_rate": OutputSpec("log", 0.0, 0.2, 0.2, "qb_line"),
        "int_rate": OutputSpec("log", 0.0, 0.2, 0.2, "qb_line"),
        "rush_yards": OutputSpec("identity", 0.0, 2500.0, 0.2, "qb_line"),
        "rush_td": OutputSpec("identity", 0.0, 30.0, 0.2, "qb_line"),
        "wins": OutputSpec("logit", 0.0, 17.0, 1.0, "team"),
    }
    base = dict(
        outputs=outputs,
        stat_line_weights={"pass_yards": 1.0, "pass_td": 1.0, "interceptions": -0.5,
                           "rating": 1.0, "rush_yards": 0.3},
        team_success_weights={"wins": 1.0, "playoff_depth": 0.5},
        award_terms={
            "mvp": {"pass_yards": 1.0, "pass_td": 1.0, "wins": 1.0},
            "opoy": {"pass_yards": 1.0, "pass_td": 1.0, "rating": 1.0},
            "all_pro": {"rating": 1.0, "pass_td": 1.0},
            "pro_bowl": {"rating": 1.0},
            "sb_mvp": {"rating": 1.0, "wins": 1.0},
        },
        distribution_points=101,
        residual_points=21,
    )
    base.update(over)
    return cfg(**base)


def world(n=240, seed=2):
    """A league whose quarterback lines and records follow the six values, with
    noise, and whose best seasons won the awards: the shape of the real thing."""
    rng = random.Random(seed)
    seasons = []
    for i, v in enumerate(values_grid(n, seed)):
        a, arm, mob, iq, bld, cast = v
        attempts = int(380 + arm + rng.uniform(-30, 30))
        ypa = linear_ypa(v) + rng.uniform(-0.3, 0.3)
        quality = (a + arm + mob + iq + bld) / 10 + cast / 2
        wins = max(0, min(17, round(17 / (1 + math.exp(-(quality - 60) / 12)) + rng.uniform(-1.5, 1.5))))
        seasons.append(season(
            i, v, attempts=attempts, ypa=ypa, wins=wins, depth=0,
            completions=int(attempts * (0.52 + 0.0022 * a + rng.uniform(-0.01, 0.01))),
            pass_tds=int(attempts * (0.02 + 0.0003 * (a + arm + iq) / 3 * 1.5)),
            interceptions=int(attempts * (0.05 - 0.0003 * iq - 0.0001 * a)),
            rush_yards=20.0 + 6 * mob, rush_tds=mob // 20,
        ))
    best = sorted(seasons, key=lambda s: -s.pass_yards)[:12]
    winners = {s.player_id: set() for s in best}
    for k, s in enumerate(best):
        winners[s.player_id] |= {"mvp"} if k < 3 else set()
        winners[s.player_id] |= {"opoy"} if k < 4 else set()
        winners[s.player_id] |= {"all_pro"} if k < 6 else set()
        winners[s.player_id] |= {"pro_bowl"}
        # As in real life, nobody has held all five in one season.
        winners[s.player_id] |= {"sb_mvp"} if k in (6, 9) else set()
    seasons = [s._replace(awards=frozenset(winners.get(s.player_id, ()))) for s in seasons]
    return seasons


def league():
    return league_from(LadderTest.TRUE, n=3000)


class FitTest(unittest.TestCase):
    def test_top_of_scale_makes_a_season_no_real_one_matched(self):
        seasons = world()
        model = fit(seasons, league(), full_cfg(ladder_ridge=1e-6))
        top = expected_metrics(model.outputs, (99,) * 6)
        real = [season_metrics(s, full_cfg()) for s in seasons]
        for metric in ("pass_yards", "pass_td", "rating"):
            self.assertGreater(top[metric], max(m[metric] for m in real), metric)
        self.assertLessEqual(top["wins"], 17.0)
        stat = composite(model, "stat_line", top)
        self.assertGreater(stat, max(composite(model, "stat_line", m) for m in real))
        self.assertEqual(percentile_of(model.distributions["stat_line"], stat), 1.0)

    def test_top_of_scale_clears_every_award_and_a_weak_build_clears_none(self):
        model = fit(world(), league(), full_cfg(ladder_ridge=1e-6))
        top = expected_metrics(model.outputs, (99,) * 6)
        weak = expected_metrics(model.outputs, (30,) * 6)
        for award in AWARDS:
            self.assertTrue(earns(model, award, top), award)
            self.assertFalse(earns(model, award, weak), award)

    def test_a_perfect_build_scores_a_perfect_hundred(self):
        model = fit(world(), league(), full_cfg(ladder_ridge=1e-6))
        top = expected_metrics(model.outputs, (99,) * 6)
        top["playoff_depth"] = 5.0
        self.assertEqual(score(model, top, set(AWARDS)), 100.0)

    def test_the_model_carries_every_piece_the_game_needs(self):
        seasons = world()
        model = fit(seasons, league(), full_cfg(ladder_ridge=1e-6))
        self.assertEqual([o.name for o in model.outputs], sorted(full_cfg().outputs))
        self.assertEqual([r.step for r in model.ladder], list(LADDER_STEPS))
        self.assertEqual([a.award for a in model.awards], list(AWARDS))
        self.assertEqual(sorted(model.distributions), ["awards", "stat_line", "team_success"])
        self.assertEqual(len(model.real), len(seasons))
        formulas = {f.name for f in model.formulas}
        self.assertEqual(formulas, {"score", "stat_line", "team_success", "awards",
                                    *(f"award_{a}" for a in AWARDS)})

    def test_it_is_deterministic_whatever_order_the_sources_arrive_in(self):
        seasons, teams = world(), league()
        a = fit(seasons, teams, full_cfg(ladder_ridge=1e-6))
        rng = random.Random(0)
        shuffled_seasons, shuffled_teams = list(seasons), list(teams)
        rng.shuffle(shuffled_seasons)
        rng.shuffle(shuffled_teams)
        b = fit(shuffled_seasons, shuffled_teams, full_cfg(ladder_ridge=1e-6))
        self.assertEqual(a, b)


if __name__ == "__main__":
    unittest.main()
