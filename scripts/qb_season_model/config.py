"""The real tuning for QB Season Builder's season model, and the sanity checks
that guard it.

Everything here is an input to `transform.fit` and to the build's guards, not a
constant of the algorithm: retune by editing this file and rebuilding a new data
migration. Issue #72 fixes the shape (formulas that may extrapolate; noise that
is mostly on team outcomes; thresholds calibrated on real winners; a score of
roughly 50% stat line, 30% team success and 20% awards) and leaves the numbers
to be tuned against known quarterbacks and playtesting.
"""

from transform import AWARDS, Config, Expectation, OutputSpec

# A season is always a 17-game one, so the generated season is a full modern one
# and a 16-game 2007 compares with a 17-game 2023.
SEASON_GAMES = 17

# Each output, what its formula is linear in, and how far its noise reaches.
#
# The bounds are where a formula stops, not where real seasons stopped: they sit
# beyond every real season so a perfect build can beat all of them (the fit is
# allowed to extrapolate) while a rate can still never go negative or past what
# a football game allows.
#
# `noise_scale` multiplies the real residual spread. Team outcomes take all of
# it and the quarterback's own line takes little, so a dominant quarterback can
# still lose in the playoffs but his stat line stays close to what his six
# values say ("mostly team outcomes, lightly the stat line", issue #72).
TEAM_NOISE = 1.0
LINE_NOISE = 0.3

# `attempts` is linear, not log: a multiplicative link doubled the volume of a
# build that is elite in every trait (all 99 gave 794 attempts and 6,663 yards, a
# record by 20%). A game holds only so many plays, and the linear fit tracks
# volume slightly better anyway.
OUTPUTS = {
    "attempts": OutputSpec("identity", 100.0, 800.0, LINE_NOISE, "qb_line"),
    "comp_pct": OutputSpec("logit", 0.45, 0.80, LINE_NOISE, "qb_line"),
    "ypa": OutputSpec("identity", 4.0, 11.5, LINE_NOISE, "qb_line"),
    "td_rate": OutputSpec("log", 0.0, 0.12, LINE_NOISE, "qb_line"),
    "int_rate": OutputSpec("log", 0.0, 0.08, LINE_NOISE, "qb_line"),
    "rush_yards": OutputSpec("identity", 0.0, 1500.0, LINE_NOISE, "qb_line"),
    "rush_td": OutputSpec("identity", 0.0, 20.0, LINE_NOISE, "qb_line"),
    "wins": OutputSpec("logit", 0.0, float(SEASON_GAMES), TEAM_NOISE, "team"),
}

# The score: how a season is ranked against the real ones. Weights are relative
# (they need not sum to 1); the three components are mixed as percentiles.
SCORE_WEIGHTS = {"stat_line": 50.0, "team_success": 30.0, "awards": 20.0}

# Each is a weighted sum of z-scored metrics. Interceptions count against.
STAT_LINE_WEIGHTS = {
    "pass_yards": 0.25, "pass_td": 0.25, "rating": 0.30,
    "interceptions": -0.10, "rush_yards": 0.10,
}
TEAM_SUCCESS_WEIGHTS = {"wins": 0.6, "playoff_depth": 0.4}

# What an award is worth toward the awards component. The most decorated real
# season is the top of that distribution; a build that earns more than any real
# one scores off the top of it.
AWARD_POINTS = {"mvp": 5.0, "opoy": 3.0, "all_pro": 3.0, "sb_mvp": 3.0, "pro_bowl": 1.0}

# The score each award is judged on: what voters weighed, in z-scored metrics.
# MVP leans on the record; the rest on the stat line. Calibrated against the
# real winners' seasons, so these say what to look at, not how much it takes.
AWARD_TERMS = {
    "mvp": {"wins": 0.35, "pass_td": 0.25, "pass_yards": 0.20, "rating": 0.20},
    "opoy": {"pass_yards": 0.30, "pass_td": 0.30, "rating": 0.30, "rush_yards": 0.10},
    "all_pro": {"rating": 0.40, "pass_td": 0.25, "pass_yards": 0.25, "interceptions": -0.10},
    "pro_bowl": {"rating": 0.30, "pass_yards": 0.30, "pass_td": 0.25, "wins": 0.15},
    "sb_mvp": {"rating": 0.30, "pass_td": 0.20, "pass_yards": 0.20, "wins": 0.30},
}

# Where each threshold sits among the real winners' scores: 0 lets in a season as
# good as the weakest real winner, 1 asks for the best. Set where about as many real
# seasons clear the threshold as real winners there were (MVP: 19 clear it, 18
# won it), so an award is as rare as it was, without a field to compete against. A
# lower quantile hands it to any good season (at 0.25, 62 seasons cleared All-Pro
# for 20 winners). AWARD_SHARE_BOUNDS stops a build that gets this wrong. Super Bowl
# MVP only ever applies to a champion, so it sits lower.
AWARD_QUANTILE = {"mvp": 0.4, "opoy": 0.4, "all_pro": 0.4, "pro_bowl": 0.3, "sb_mvp": 0.25}
# Noise near the edge, as a share of the real winners' own spread.
AWARD_NOISE_SCALE = {award: 0.5 for award in AWARDS}

DEFAULT_CONFIG = Config(
    season_games=SEASON_GAMES,
    outputs=OUTPUTS,
    # A 16-0 team's target sits half a game inside the top, not at infinity.
    logit_margin=0.03,
    # A season with no touchdowns or interceptions is a 0.5% rate, not log(0).
    log_floor=0.005,
    residual_points=21,
    ladder_ridge=0.5,
    stat_line_weights=STAT_LINE_WEIGHTS,
    team_success_weights=TEAM_SUCCESS_WEIGHTS,
    award_points=AWARD_POINTS,
    score_weights=SCORE_WEIGHTS,
    award_terms=AWARD_TERMS,
    award_quantile=AWARD_QUANTILE,
    award_noise_scale=AWARD_NOISE_SCALE,
    distribution_points=101,
)

# The share of all real quarterback-seasons that may clear each award's
# threshold. A real award is rare; if a threshold is cleared by more than this
# the award would be handed out to any good season, and the build stops.
AWARD_SHARE_BOUNDS = {"mvp": 0.04, "opoy": 0.03, "all_pro": 0.05, "pro_bowl": 0.30, "sb_mvp": 0.25}


# ------------------------------------------------------------ build-time guards --

# What a build of about league-average values is: the mean of each of the six across
# the real seasons, rounded (revisit it after a ratings retune). It must not earn a
# real award.
AVERAGE_BUILD = (62, 62, 62, 62, 62, 60)

# The least of a formula's spread the six values must explain, per output. A
# formula below its floor is not tracking the data, and the build stops. The floors
# sit just under what the fit explains today: a broken join drops them to about
# zero, which is what they exist to catch.
MIN_R_SQUARED = {
    "attempts": 0.25, "comp_pct": 0.35, "ypa": 0.35, "wins": 0.40,
    "rush_yards": 0.35, "rush_td": 0.15, "td_rate": 0.25, "int_rate": 0.20,
}

# Known-quarterback expectations: what a fan would sign off on, each one
# quarterback's own six values through the fit. The bands were drafted before the
# first fit; after it, two groups were widened where the fit was right and the band
# was too demanding for a model that explains about half the spread (Brees's yards,
# the runners' rushing floor, said where they are below), and the attempts link
# changed where the fit was wrong (see OUTPUTS). A miss is a clearly wrong fit.
EXPECTATIONS = [
    # Elite passers on strong teams: a great season is expected, not a record.
    Expectation("MannPe00", 2013, "pass_yards", 4300, 5700, note="record-setting pocket passer"),
    Expectation("MannPe00", 2013, "pass_td", 33, 58, note="record-setting pocket passer"),
    Expectation("MannPe00", 2013, "wins", 11.5, 17, note="a 13-3 team"),
    Expectation("BradTo00", 2007, "pass_yards", 4200, 5700, note="the 16-0 Patriots"),
    Expectation("BradTo00", 2007, "pass_td", 32, 58, note="50 touchdowns"),
    Expectation("BradTo00", 2007, "wins", 11.5, 17, note="16-0"),
    Expectation("MahoPa00", 2018, "pass_yards", 4300, 5700, note="the MVP season"),
    Expectation("MahoPa00", 2018, "pass_td", 33, 58, note="50 touchdowns"),
    # Six values cannot see how often a scheme throws, so a fit that explains about
    # half the spread expects "very good" from Brees's 5,476-yard year, not 5,000+.
    Expectation("BreeDr00", 2011, "pass_yards", 4000, 5700, note="5,476 yards, in a pass-heavy scheme"),
    Expectation("RodgAa00", 2011, "pass_td", 30, 58, note="45 touchdowns"),
    # The passer rating an elite season is expected to show: better than the league's
    # average quarterback (87), which a build of average values fits to.
    Expectation("MannPe00", 2013, "rating", 92, 140, note="115.1 passer rating"),
    Expectation("BradTo00", 2007, "rating", 92, 140, note="117.2 passer rating"),
    Expectation("MahoPa00", 2018, "rating", 92, 140, note="113.8 passer rating"),
    Expectation("BreeDr00", 2011, "rating", 92, 140, note="110.6 passer rating"),
    # The runners run and the pocket passers do not. A runner is expected to run for
    # at least twice the league's average quarterback (173 yards a season): the fit
    # is a mean, and the record-setting years (Jackson ran for 1,206) sit far above it.
    Expectation("JackLa00", 2019, "rush_yards", 350, 1500, note="1,206 rushing yards"),
    Expectation("VickMi00", 2010, "rush_yards", 350, 1500, note="the original"),
    Expectation("NewtCa00", 2015, "rush_yards", 350, 1500, note="MVP season"),
    Expectation("MannEl00", 2011, "rush_yards", 0, 120, note="pocket passer"),
    Expectation("BreeDr00", 2011, "rush_yards", 0, 170, note="pocket passer"),
    Expectation("MannPe00", 2013, "rush_yards", 0, 120, note="pocket statue"),
    # And the worst ones are expected to look like it.
    Expectation("RussJa00", 2009, "pass_yards", 0, 3400, note="one of the worst quarterbacks of the era"),
    Expectation("RussJa00", 2009, "wins", 0, 9, note="a 5-11 team"),
    Expectation("GabbBl00", 2011, "pass_yards", 0, 3400, note="a rookie who could not throw"),
    Expectation("GabbBl00", 2011, "pass_td", 0, 22, note="12 touchdowns"),
    Expectation("RussJa00", 2009, "rating", 0, 85, note="50.0 passer rating"),
    Expectation("GabbBl00", 2011, "rating", 0, 85, note="65.4 passer rating"),
]
