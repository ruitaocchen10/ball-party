"""The real tuning for QB Season Builder's season model, and the sanity checks
that guard it.

Everything here is an input to `transform.fit` and to the build's guards, not a
constant of the algorithm: retune by editing this file and rebuilding a new data
migration. Issue #72 fixes the shape (formulas that may extrapolate; noise that
is mostly on team outcomes; thresholds calibrated on real winners; a score of
roughly 55% stat line, 30% team success and 15% awards) and leaves the numbers
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
# it and the quarterback's own line takes less, so a dominant quarterback can
# still lose in the playoffs but his stat line stays near what his six values say
# ("mostly team outcomes, lightly the stat line", issue #72).
#
# How much less is a judgment. Replaying all 777 real builds 20 times each, the real season
# landed inside the generated middle 80% of yards, touchdowns, interceptions and rush yards:
#   noise 0.3  about 30% of the time (the same build gave nearly the same line every run;
#              interceptions varied half as much as real life)
#   noise 0.5  about 45-50%
#   noise 0.6  about 55%, but a top build broke the passing-yards record in 1 run of 20
#   noise 1.0  about 75% (the real spread, and the six values then decide little of a line)
# 0.5 lets a line move enough to feel like a season and still be its build's. More line noise
# also makes rare awards more common (they sit in the tail of the stat line), so the award
# quantiles below were set with it in place: replaying the real builds gives the real rates.
#
# Team outcomes took the whole real spread (1.0) and are now held to 0.8, to take some luck out
# of the score: the same well-drafted build scored about 10 points apart run to run, and wins
# and the bracket are the largest share of it. It is a trade, not a free one. The real season's
# wins landed inside its build's generated middle 80% of wins 76% of the time at 1.0 and 66% at
# 0.8, so wins are now a little tighter than real life; playoffs (34.9% against 35.1% real) and
# the title (2.6% against 2.7%) still match. Lower costs more: in the fit's own replay 0.65 gave
# a title rate of 2.1% and 0.5 gave 1.9%.
TEAM_NOISE = 0.5
LINE_NOISE = 0.3

# The five quarterback values are read off overlapping stats (CPOE, EPA and air yards feed
# Accuracy, Arm Talent and IQ; playing time feeds Build and IQ), and Accuracy and IQ
# correlate at 0.83. Plain least squares gives the whole of a shared effect on wins to
# whichever of them it weighs a hair more, so IQ got nearly everything and Accuracy none,
# an accident of the fit and not football: alone, Accuracy is worth 6.9 wins from 25 to 99
# and IQ 8.0. A ridge on the five makes them share it. The Supporting Cast is left out of
# the penalty: it is not tangled with them, and a penalty there only shrinks the best
# measured effect in the model. Swept from 0.1 to 2 on the real fit: Accuracy's share
# peaks around 0.3-0.6 and falls after, and at 0.6 Accuracy and Build come out level. It
# costs nothing in fit (R2 0.62 either way).
WINS_RIDGE = 0.6
QB_SLOTS = ("accuracy", "arm_talent", "mobility", "iq", "build")

# The Supporting Cast's effect on wins is held at this share of what the data give it, and
# the quarterback values are refit around it. The cast is partly built from Approximate
# Value, which is itself derived from how well the team did, so its link to wins is
# overstated: 0.78 with AV in the blend, 0.52 in 2019 where the cast is Madden alone. A
# judgment, not a measurement, so it is a knob. Swept 1.0 to 0.6 on the real fit: down to
# 0.8 it costs nothing in fit (R2 0.612 against 0.614) and the quarterback values absorb the
# difference; at 0.7 the fit starts to suffer. At 0.8 a value is worth this many wins from
# 25 to 99 (others average): cast about 8.4, IQ 1.9, Accuracy 1.1, Build 1.0, Arm Talent
# 0.7, Mobility 0.4.
CAST_WINS_TRIM = 0.8

# `attempts` saturates: a logit link between 100 and ATTEMPTS_CAP. It was linear, which
# fits the steep part of the real data (a starter throws far more than a backup, so the
# formula climbs with Build, IQ and Accuracy) and then keeps climbing where the real data
# go flat: real seasons in the top build buckets throw 540-560 passes, and a straight line
# asked for 650-690 from the same builds. The cost showed up in play. A player who drafts
# well is stacking 90s, and 4.2% of those runs came out at 680+ attempts (0.6% of real
# seasons did) and 2.5% at 5,500+ yards (a record by a margin nobody believes).
#
# Replaying the same 18,000 simulated builds with a cap of 640 / 670 / 700 / 740 gave
# 5,500+ yards in 0.10 / 0.15 / 0.40 / 1.10% of well-drafted runs, against 0.26% of real
# seasons. 670 keeps a record-level passer reachable (the best-drafted runs' 99th percentile
# is 5,294 yards, where real seasons' is 5,419 scaled to 17 games) and costs nothing in fit
# (R2 0.451 against 0.467); every guard below still holds. A multiplicative (log) link was
# the other thing tried, and doubled the volume of a build that is elite in every trait
# (all 99: 794 attempts and 6,663 yards); the logit is bounded, so it cannot.
ATTEMPTS_CAP = 670.0

# Balancing what each value is worth. Left to the fit, a value's swing on the score (25 to 99, the
# rest as they were) ran from IQ 32.5 and Supporting Cast 28.2 down to Build 12.9, Mobility 16.1
# and Arm Talent 7.3: 4.4 to 1. The data really do say Arm Talent adds little once Accuracy and IQ
# are known, but a slot worth a fifth of another is a round that hardly matters, so the game
# leans against it (issue #72 leaves the numbers to playtesting). A trim holds a value's
# coefficient at a multiple of the fitted one and refits the rest around it, so what a value is
# given is taken from the values it is tangled with, mostly IQ and Accuracy.
#
# Each is a multiple of the fitted coefficient, on the outputs where the value has an effect.
# Swept over Arm 1.5-3, Build's wins 1-4 and Mobility's rushing 1-1.5, keeping the cheapest
# (in fit) setting where the biggest swing is under twice the smallest and none is under 15:
#   Arm Talent x2.5 on yards per attempt, touchdown rate and wins. x2 left it at 12.8.
#   Build x3 on wins (its own yards and touchdown coefficients are held where the fit put them).
#   Mobility x1.25 on rush yards and rush touchdowns, where it does its work.
# With the score changes below, swings are IQ 28.0, Supporting Cast 26.0, Accuracy 23.3,
# Mobility 16.6, Build 16.5 and Arm Talent 15.4 (1.82 to 1), measured on the real builds in the
# database. It costs fit, and that is the price: yards per attempt R2 0.558 to 0.483, touchdown
# rate -0.023, rush yards -0.031, wins -0.011. Every guard below still holds.
ARM_TALENT_SHARE = 2.5
BUILD_WINS_SHARE = 3.0
MOBILITY_RUSH_SHARE = 1.25

# What the Supporting Cast does to the quarterback's own line. The data give it a real but small
# effect on yards per attempt and touchdown rate (regression on the 777 seasons: t = 4.8 and 5.5;
# one standard deviation of cast, about 16 points, is worth 0.12 yards a pass against 0.58 of
# noise) and, if anything, fewer passes (t = -1.7, not distinguishable from zero: a better team
# leads more and throws less). Left as fitted, going from a Cast of 25 to 99 changed a season by
# -84 passing yards and +4 touchdowns, which reads as the cast not mattering to a stat line.
# A judgment, not a measurement: the cast's effect on yards per attempt and touchdown rate is
# held at this multiple of the fit (1.5 is 2.4 standard errors above the regression for yards
# per attempt), and its effect on attempts at this share (0: no effect).
# Measured on the real builds, 25 to 99: +382 yards and +9 touchdowns, and the cast's swing on
# the score 26.1 to 32.8 (the largest of the six), so the biggest swing is 2.16 times the
# smallest and not 1.82. Yards per attempt R2 0.483 to 0.478, touchdown rate 0.463 to 0.457.
CAST_LINE_SHARE = 1.5
CAST_ATTEMPTS_SHARE = 0.0

# Whether a quarterback who played better than his values predicted also won more. In the data
# only a little: the wins residual correlates +0.06 to +0.13 with each of the line residuals
# (0.13 with all four together, which would shrink the record's noise by 1%). In the game
# that left the record independent of the line, so a build whose passing came out average
# could go 12-5 as easily as one whose passing came out great. This makes it so a little more
# than the data say (0.3, by judgment, and a knob): the record's own spread is unchanged,
# a build's average record is unchanged, and only the pairing of a lucky line with a lucky
# record is.
WINS_LINE_LINK = 0.3

OUTPUTS = {
    "attempts": OutputSpec("logit", 100.0, ATTEMPTS_CAP, LINE_NOISE, "qb_line",
                           trim=(("supporting_cast", CAST_ATTEMPTS_SHARE),)),
    "comp_pct": OutputSpec("logit", 0.45, 0.80, LINE_NOISE, "qb_line"),
    "ypa": OutputSpec("identity", 4.0, 11.5, LINE_NOISE, "qb_line",
                      trim=(("arm_talent", ARM_TALENT_SHARE), ("build", 1.0),
                            ("supporting_cast", CAST_LINE_SHARE))),
    "td_rate": OutputSpec("log", 0.0, 0.12, LINE_NOISE, "qb_line",
                          trim=(("arm_talent", ARM_TALENT_SHARE), ("build", 1.0),
                                ("supporting_cast", CAST_LINE_SHARE))),
    "int_rate": OutputSpec("log", 0.0, 0.08, LINE_NOISE, "qb_line"),
    "rush_yards": OutputSpec("identity", 0.0, 1500.0, LINE_NOISE, "qb_line",
                             trim=(("mobility", MOBILITY_RUSH_SHARE),)),
    "rush_td": OutputSpec("identity", 0.0, 20.0, LINE_NOISE, "qb_line",
                          trim=(("mobility", MOBILITY_RUSH_SHARE),)),
    "wins": OutputSpec("logit", 0.0, float(SEASON_GAMES), TEAM_NOISE, "team",
                       ridge=WINS_RIDGE, ridge_slots=QB_SLOTS,
                       trim=(("supporting_cast", CAST_WINS_TRIM), ("arm_talent", ARM_TALENT_SHARE),
                             ("build", BUILD_WINS_SHARE))),
}

# The score: how a season is ranked against the real ones. Weights are relative
# (they need not sum to 1); the three components are mixed as percentiles.
#
# It was 50 / 30 / 20. The same build then scored about 10 points apart run to run (the
# standard deviation over seeds, for a well-drafted one), and most of that was not the stat
# line: per point of weight a component's own variance is about 0.003 for the stat line,
# 0.04 for team success (wins and the playoff bracket) and 0.08 for awards, which are a step
# (a Pro Bowl alone ranks above 3 real seasons in 4, worth 15 of the 20 points). Moving 5
# points from awards to the stat line takes that to about 8. Real award rates, the playoff
# ladder and the noise are untouched, and the mean score moves up a couple of points, which
# SCORE_CURVE gives back at the top.
SCORE_WEIGHTS = {"stat_line": 55.0, "team_success": 30.0, "awards": 15.0}

# A soft ceiling on the finished score: below the start it is unchanged, above it the score
# is start + (100 - start) * ((score - start) / (100 - start)) ** exponent, so 0 and 100 stay
# put. Ranking a season against the real ones only leaves a drafted build no room: a player
# stacking 80s and 90s is better than nearly every real season on the stat line, so the top
# of the score is decided by whether the awards and the bracket come off. Balancing the six
# values (above) made that worse, lifting every above-average build about 1.5 points and the
# share of well-drafted runs at 90+ from 14% to 18%. Trimming the strong values instead does
# nothing (redistributing credit leaves the sum of a stacked build's effects where it was),
# and tightening award thresholds costs real rates (an All-Pro cutoff of 0.6 gives 1.0% MVPs
# against 2.3% real). A start of 70 with exponent 1.5 takes 90+ from a well-drafted run (a
# skilled drafter who respins) from 14% before the balancing to 11%, and leaves the ladder of
# drafters where it was: random 47, greedy 72, skilled 78 (45, 70, 77 before). A raw 90 reads
# as 86 and a raw 80 as 75 (1.5: 86 and 76); 0 and 100 stay put. The record's link to the line (WINS_LINE_LINK)
# and the cast's effect on the line (CAST_LINE_SHARE) put well-drafted runs back up to 12.5-13.7%
# at 90+ (a lucky line and a lucky record now come together); an exponent of 1.6 takes that to
# about 11.7% (1.7 gives 10.9%, 1.9 gives 9.4%) at a cost of about half a point of mean score.
SCORE_CURVE = (70.0, 1.6)

# Each is a weighted sum of z-scored metrics. Interceptions count against.
#
# Rushing is a fifth of the stat line, and its touchdowns a tenth. It was a tenth, with no
# touchdowns, and a quarterback's Mobility then moved a season's score by 10 points from 25
# to 99 (Accuracy 29, IQ 34) because rushing was the only thing it changed: a runner and a
# pocket passer were not comparable (a 25-Mobility pocket passer scored 79, a 99-Mobility
# runner with no arm 22). Mobility is now worth about 19 and Build, whose volume carries
# passing yards but whose interceptions and passer rating cut the other way, about 14.
# Interceptions count for less (a count, so they charge volume as much as carelessness).
# Arm Talent stays small on purpose: given Accuracy and IQ, the data give it the least of
# any value, and a bigger score weight would be an effect the 20 seasons do not show.
STAT_LINE_WEIGHTS = {
    "pass_yards": 0.25, "pass_td": 0.20, "rating": 0.20,
    "interceptions": -0.05, "rush_yards": 0.20, "rush_td": 0.10,
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
    "mvp": {"wins": 0.50, "pass_td": 0.15, "pass_yards": 0.10, "rating": 0.15, "rush_yards": 0.10},
    "opoy": {"pass_yards": 0.30, "pass_td": 0.30, "rating": 0.30, "rush_yards": 0.10},
    "all_pro": {"wins": 0.35, "rating": 0.25, "pass_td": 0.15, "pass_yards": 0.15, "rush_yards": 0.05, "interceptions": -0.05},
    "pro_bowl": {"rating": 0.30, "pass_yards": 0.30, "pass_td": 0.25, "wins": 0.15},
    "sb_mvp": {"rating": 0.30, "pass_td": 0.20, "pass_yards": 0.20, "wins": 0.30},
}

# Where each threshold sits among the real winners' scores: 0 lets in a season as
# good as the weakest real winner, 1 asks for the best. Set where about as many real
# seasons clear the threshold as real winners there were (MVP: 18 clear it, 18 won it, once
# it also has to be an All-Pro: see AWARD_REQUIRES), so an award is as rare as it was,
# without a field to compete against. A lower quantile hands it to any good season (at
# 0.25, 62 seasons cleared All-Pro for 20 winners). AWARD_SHARE_BOUNDS stops a build that
# gets this wrong. Super Bowl MVP only ever applies to a champion, so it sits lower. The
# quantiles are then checked the way the game uses them, by generating 20 seasons from each
# real build with the noise on: MVP 2.0%, Offensive Player of the Year 1.0%, All-Pro 2.9%,
# Pro Bowl 22.8% and Super Bowl MVP 1.7% of seasons, against 2.3, 1.0, 2.6, 23.7 and 1.7 real.
# A sparse award (8 real Offensive Players of the Year) is sensitive: 0.4 gave 2.2%, 0.6 gave 0.4%.
#
# All-Pro moved from 0.45 to 0.5 and Pro Bowl from 0.3 to 0.33 once the values were balanced:
# replaying the real builds then gave All-Pro 3.3% and Pro Bowl 24.6% of seasons against 2.6%
# and 23.7% real. Now 2.8% and 23.7%, MVP 2.2% against 2.3%. (That was before All-Pro took
# wins into account: see below.)
AWARD_QUANTILE = {"mvp": 0.05, "opoy": 0.50, "all_pro": 0.64, "pro_bowl": 0.33, "sb_mvp": 0.25}
# The last retune (All-Pro 0.55, OPOY 0.45) was fitted with the record independent of the
# line and the cast worth nothing to a stat line. Linking them (WINS_LINE_LINK) and giving the
# cast its effect (CAST_LINE_SHARE) put more seasons with both a big line and a big record in the
# same place, and replaying the real builds gave MVP 2.6-2.9%, All-Pro 2.9-3.3% and Offensive
# Player of the Year 1.3-1.5% against 2.3, 2.6 and 1.0 real. Now, averaged over six sets of seeds
# (a single set moves MVP by 0.2): MVP 2.4%, All-Pro 2.5%, OPOY 1.0%, Pro Bowl 24.0% (23.7 real),
# Super Bowl MVP 1.8% (1.7). All-Pro is sharp here: 0.60 gives 2.9%, 0.65 gives 2.3%.
# Noise near the edge, as a share of the real winners' own spread.
AWARD_NOISE_SCALE = {award: 0.5 for award in AWARDS} | {"all_pro": 1.25}
# All-Pro is judged on wins as well as the stat line, and its gate is wide. An MVP must be an
# All-Pro (AWARD_REQUIRES) and All-Pro used to ignore the record, so a real MVP like Brady's 2017
# (13-3, 4,863 yards, 34 TDs, 102.8) had no chance at all: 6 of the 18 real MVPs (Manning 2008 and
# 2009, Newton 2015, Brady 2017, Jackson 2023, Allen 2024) were impossible, and the odds of the rest
# were a step where the real odds are a slope (of the real seasons that score 1.3 to 1.5 on the MVP
# formula 29% won it, 1.1 to 1.3 5%, 1.7 to 2.0 57%). The wins term (0.35), the 0.55 quantile and the
# wider noise were fitted to the 20 real years by the likelihood of the real winners, and hold up
# fitted on one decade and tested on the other, in both directions. Scored on the real seasons:
# All-Pro 20.1 seasons against 20 real, MVP 17.8 against 18; 1 real MVP is now impossible (Manning
# 2008), 2 are under 5% (that and Allen 2024, 3%) and Brady 2017 is 18%. The kind of season with
# 12.5+ wins, 4,300+ yards and 33+ TDs is now 41% to win it (8 of the 28 real ones did, 29%): there is
# no field to beat, so it runs generous, and a runner with a light passing line still gets little
# (Jackson 2023, 6%).
# Awards nest, as they did in 2006-2025: of 18 quarterback MVPs, 17 were first-team All-Pro
# and all 18 went to the Pro Bowl; all 20 All-Pros did too; all but 2 of 8 Offensive Players
# of the Year were All-Pro. Judged on their own scores, 46% of generated MVPs were not
# even All-Pro (6% in real life) and a season could take the MVP and miss the Pro Bowl.
# (Super Bowl MVP is not tied: 5 of 13 real ones were not Pro Bowlers.)
AWARD_REQUIRES = {"mvp": "all_pro", "opoy": "pro_bowl", "all_pro": "pro_bowl"}

# How hard the game is. The formulas are fitted on real seasons, and a player who drafts well is
# stacking values a real quarterback rarely has all at once, so a strong build ran further ahead
# of the real league than the game wanted: a skilled drafter who respins won MVP 8.0% of the time
# (2.3% of real seasons), scored 90+ in 11.8% of runs and had a rating of 100+ in 47%.
# The values a season is built from are counted in full up to VALUE_PIVOT and above it only
# VALUE_SLOPE of each point counts, so a 90 plays like an 87 and a 99 like a 94 (the six values
# are all treated the same, the Supporting Cast too). It leaves the floor alone, which is why it
# beats an across-the-board handicap: a poor start is no poorer (the worst drafter's score
# 22.8 to 22.6) and it is the strong builds that come down.
# Replayed on the same drafted builds, at a slope of 0.9 / 0.8 / 0.7, a skilled drafter who
# respins goes: MVP 8.0% to 5.8 / 3.9 / 2.4, 90+ 11.8% to 8.8 / 6.0 / 4.0, a rating of 100+ 47%
# to 41 / 35 / 29, playoffs 74.8% to 73.0 / 71.1 / 68.9, a conference final or better
# 26.7% to 25.0 / 23.5 / 22.0 and the title 6.6% to 6.0 / 5.4 / 5.0. Replaying the real builds
# no longer gives the real league on the strong end (that is the point): MVP 2.2% to 1.5 / 1.0 / 0.5.
# 1 turns it off; lower is harder.
# 0.85 is the setting, as measured in the database (0.9 and 0.8 above are the same replay before the
# curve existed in SQL): a skilled drafter who respins wins MVP 4.9% (8.0), scores 90+ 7.3% (11.8),
# has a rating of 100+ 38.7% (47.0), makes the playoffs 72.1% (74.8), reaches a conference final
# or better 24.2% (26.7) and wins the title 5.6% (6.6), and the mean score is 74.8 (77.1). Random
# 45.8 (47.2), the worst 22.4 (22.8). The six values' swings come down together, so their balance
# holds (biggest over smallest 2.17; Arm Talent's 14.4, a little under the 15 it was held to), and
# score luck goes from 8.2 to 8.6 points, 49.7% of the variance (47.3). Replaying the real builds:
# MVP 1.2% (2.3 real), All-Pro 1.3% (2.6), Pro Bowl 21.9% (23.7), the title 2.4% (2.7), wins 8.0 (8.1).
# The award thresholds were calibrated to real rates and are not retuned for this: an award for a
# strong build is meant to be harder.
VALUE_PIVOT = 70.0
VALUE_SLOPE = 0.81
VALUE_CURVE = (VALUE_PIVOT, VALUE_SLOPE)

# Where the playoff ladder is sharper than a logistic in wins can be: (never at or below,
# always at or above), in wins per 17 games. Of the real 2006-2025 teams, none of the 105
# with 12 or more wins missed the playoffs and none of the 109 with 5 or fewer made them,
# yet the fitted curve lets a 13-4 team miss 1 time in 520 and a 12-5 one 1 in 87. That is
# rare enough to be invisible in a fit and common enough for a player to meet within a few
# hundred runs, and a 13-4 team out of the playoffs reads as a broken game. A guard in
# build_model.py fails the build if the real data ever contradict either end.
LADDER_GUARANTEES = {"make_playoffs": (5, 12)}

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
    award_requires=AWARD_REQUIRES,
    ladder_guarantees=LADDER_GUARANTEES,
    score_curve=SCORE_CURVE,
    wins_link=WINS_LINE_LINK,
    value_curve=VALUE_CURVE,
    distribution_points=101,
)

# The share of all real quarterback-seasons that may clear each award's
# threshold. A real award is rare; if a threshold is cleared by more than this
# the award would be handed out to any good season, and the build stops.
AWARD_SHARE_BOUNDS = {"mvp": 0.04, "opoy": 0.03, "all_pro": 0.05, "pro_bowl": 0.30, "sb_mvp": 0.25}


# ------------------------------------------------------------ build-time guards --

# How many real seasons may still beat a top-of-scale build's *expected* stat line, and the
# lowest percentile of the real stat-line distribution it may score. A fitted formula
# regresses toward the mean, so a perfect build's expected line lands near the record, not
# far above it; the noise on top is what carries it past. The strict "beats every real
# season" form was met by 0.13 before the IQ retune to passing EPA and missed by 0.012
# after; a tolerance of 0.05 below the best season then held until rushing became a third
# of the stat line, when the best real season became a single outlier (Lamar Jackson 2019,
# 1,281 rushing yards, 5.9 sd; 2.30 against the perfect build's 2.02). That build still
# beats every real season but two (both his), and the real 99th percentile (1.64) by a wide
# margin. More than that many above it is a formula that cannot extrapolate.
TOP_BUILD_MAX_BEATEN = 2
TOP_BUILD_MIN_PERCENTILE = 0.99

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
