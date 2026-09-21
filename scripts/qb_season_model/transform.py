"""Real seasons + tuning -> QB Season Builder's fitted season model.

This module is the one seam in the season-model build: parsed source rows and a
`Config` in, the finished model out. It is a pure function. No network, no
filesystem, no clock, and no constant a caller cannot replace: every link,
weight, quantile and noise scale arrives in `Config`, which is how the tests can
pass their own tuning and how the real numbers can be retuned without touching
this file. Fetching, guards and artifact writing stay outside it.

What it turns the six rating values (issue #72, "Season generation") into:

* an *expected season*: a stat line and expected wins, each a fitted formula of
  the six values. The formulas are fitted, so a build above anything real
  extrapolates above anything real, rather than being clamped to the sample;
* the *residual spread* around each formula, per output, as a quantile table, so
  noise can be drawn from the real spread and bounded by it, and applied mostly
  to team outcomes and lightly to the quarterback's own line;
* the *playoff ladder*: the chance of each round as a function of wins;
* *award thresholds* calibrated on the stat lines and records of the real
  winners;
* the *score distribution*: how the real seasons spread on stat line, team
  success and awards, so a generated season can be ranked against them.

Everything is expressed per full season (`Config.season_games` games) so that
seasons of 16 and 17 games are comparable.
"""

import math
from collections import defaultdict
from typing import Mapping, NamedTuple

# The formula outputs a Config may fit, each per full season: volume, the rates
# a passing line is made of, the rushing line, and expected wins.
LINE_OUTPUTS = ("attempts", "comp_pct", "ypa", "td_rate", "int_rate",
                "rush_yards", "rush_td", "wins")

# What a season is measured on, per full season. The score and awards read these.
METRICS = ("pass_yards", "pass_td", "interceptions", "rating", "rush_yards",
           "rush_td", "wins", "playoff_depth")
SCORE_COMPONENTS = ("stat_line", "team_success", "awards")

SLOTS = ("accuracy", "arm_talent", "mobility", "iq", "build", "supporting_cast")
AWARDS = ("mvp", "opoy", "all_pro", "pro_bowl", "sb_mvp")

# The playoff rounds a team can reach, in order. A team's `playoff_depth` is how
# many of them it played in (a bye team never plays a wild card game but does
# play the divisional one), plus one for winning the last.
ROUNDS = ("WC", "DIV", "CON", "SB")
LADDER_STEPS = ("make_playoffs", "reach_divisional", "reach_conference",
                "reach_super_bowl", "win_super_bowl")


class OutputSpec(NamedTuple):
    """How one fitted output is shaped.

    `link` is the transform its formula is linear in:
      identity  y = z, clamped to [low, high] when predicted
      log       y = exp(z), so it can never go negative; `high` caps it
      logit     y = low + (high - low) * sigmoid(z), so it can never leave [low, high]
    `noise_scale` multiplies this output's residual spread when noise is drawn
    for it: near 1 for team outcomes, small for the quarterback's own line.
    `group` is `team` or `qb_line`, for whoever applies the noise.
    `ridge` penalises the formula's slopes (0 is ordinary least squares), in units
    of the standardised values: the six are not independent (Accuracy and IQ
    correlate at 0.8), and plain least squares hands the credit for what they
    share to whichever it happens to weigh a hair more. A ridge splits it.
    `ridge_slots` names the values the penalty applies to (empty means all six):
    penalising a value that is not tangled with anything, like the Supporting
    Cast, only shrinks a well-measured effect.
    `trim` is pairs of (value, factor): that value's coefficient is held at
    `factor` times what a full fit gives it, and the other values are refit
    around it, so they pick up what the trimmed one was claiming. For an effect
    the data overstate (a value partly built from the outcome it predicts).
    """

    link: str
    low: float
    high: float
    noise_scale: float
    group: str
    ridge: float = 0.0
    ridge_slots: tuple = ()
    trim: tuple = ()


class Config(NamedTuple):
    """Every tuning input. Nothing in this module reads a constant instead."""

    # A season is normalised to this many games, so 16- and 17-game seasons
    # compare and the generated season is always a full one.
    season_games: int
    # output name -> OutputSpec. Names are LINE_OUTPUTS' keys.
    outputs: Mapping[str, OutputSpec]
    # A logit-linked target is clamped this far (as a share of the range) from
    # its ends, so a 16-0 season is a large number and not an infinite one.
    logit_margin: float
    # A log-linked target is floored here, so a season with no touchdowns is a
    # small rate and not log(0). Well below any ordinary rate.
    log_floor: float
    # How many points the residual quantile table has (>= 2), evenly from 0 to 1.
    residual_points: int
    # Ridge penalty on the playoff ladder's slope, so a rung a team can hardly
    # miss does not fit an infinite one.
    ladder_ridge: float
    # metric -> weight, over the z-scored metrics, for the two score components.
    stat_line_weights: Mapping[str, float]
    team_success_weights: Mapping[str, float]
    # award -> points, for the third score component.
    award_points: Mapping[str, float]
    # component -> weight, e.g. roughly 50 / 30 / 20.
    score_weights: Mapping[str, float]
    # award -> {metric: weight}: the score each award is judged on.
    award_terms: Mapping[str, Mapping[str, float]]
    # award -> the quantile of the real winners' scores the threshold sits at
    # (0 = the weakest real winner would still take it), and how much noise to
    # apply near it, as a share of the winners' own spread.
    award_quantile: Mapping[str, float]
    award_noise_scale: Mapping[str, float]
    # How many points the score distribution tables have (>= 2).
    distribution_points: int
    # award -> the award it requires: a season that misses the required one cannot
    # take this one, however good its own score. Real awards nest this way (an MVP
    # is nearly always an All-Pro), and judged alone they do not. Optional.
    award_requires: Mapping[str, str] = None


# ------------------------------------------------------------------- inputs --


class QbLine(NamedTuple):
    """One quarterback's regular-season totals with one franchise."""

    franchise_code: str
    season: int
    player_id: str          # Pro Football Reference id
    attempts: int
    completions: int
    pass_yards: float
    pass_tds: int
    interceptions: int
    rush_yards: float
    rush_tds: int


class TeamSeason(NamedTuple):
    """One franchise's regular-season record and how far it went."""

    franchise_code: str
    season: int
    wins: int
    losses: int
    ties: int
    playoff_depth: int      # 0 missed .. 4 lost the Super Bowl, 5 won it


class RatedSeason(NamedTuple):
    """One row of the ratings pipeline's output, with the team's cast joined on."""

    franchise_code: str
    season: int
    player_id: str
    display_name: str
    accuracy: int
    arm_talent: int
    mobility: int
    iq: int
    build: int
    supporting_cast: int


class Award(NamedTuple):
    season: int
    award: str
    player_id: str


class Expectation(NamedTuple):
    """A known-quarterback sanity check on the fitted season.

    The quarterback's own six values go through the fit and one metric of the
    expected season must land in [low, high]. `franchise_code` '' means whichever
    team he threw the most for that season.
    """

    player_id: str
    season: int
    metric: str
    low: float
    high: float
    franchise_code: str = ""
    note: str = ""


class RealSeason(NamedTuple):
    """A real quarterback-season: the six values and everything that happened."""

    franchise_code: str
    season: int
    player_id: str
    display_name: str
    accuracy: int
    arm_talent: int
    mobility: int
    iq: int
    build: int
    supporting_cast: int
    attempts: int
    completions: int
    pass_yards: float
    pass_tds: int
    interceptions: int
    rush_yards: float
    rush_tds: int
    wins: int
    losses: int
    ties: int
    playoff_depth: int
    awards: frozenset


# ---------------------------------------------------------------- the rating --


def passer_rating(completions, attempts, yards, tds, interceptions):
    """The NFL passer rating, 0 to 158.3."""
    if attempts <= 0:
        return 0.0

    def cap(x):
        return max(0.0, min(2.375, x))

    a = cap((completions / attempts - 0.3) * 5)
    b = cap((yards / attempts - 3) * 0.25)
    c = cap(tds / attempts * 20)
    d = cap(2.375 - interceptions / attempts * 25)
    return (a + b + c + d) / 6 * 100


# ---------------------------------------------------------------- aggregate --


def _num(value):
    """A weekly-stats cell as a float; blank and 'NA' are zero."""
    if value is None:
        return 0.0
    value = value.strip()
    if value in ("", "NA"):
        return 0.0
    return float(value)


def qb_lines_from_weeks(week_rows, pfr_ids, franchise_codes):
    """nflverse weekly rows -> one QbLine per (quarterback, team, season).

    `pfr_ids` maps a GSIS id to a Pro Football Reference id; a player it cannot
    resolve is left out, because the only lines that are used are those joined
    to a rated season, and a rated season always has an id. Every quarterback
    who threw a pass is aggregated, not only the ones who qualify: the
    qualifying rule belongs to the ratings and this is joined to them.
    """
    totals = {}
    for row in week_rows:
        if row["season_type"] != "REG" or row["position"] != "QB":
            continue
        if _num(row["attempts"]) <= 0 or row["player_id"] not in pfr_ids:
            continue
        team = row["team"]
        if team not in franchise_codes:
            raise ValueError(f"no franchise code for nflverse team {team!r}")
        key = (franchise_codes[team], int(row["season"]), pfr_ids[row["player_id"]])
        t = totals.setdefault(key, defaultdict(float))
        t["attempts"] += _num(row["attempts"])
        t["completions"] += _num(row["completions"])
        t["pass_yards"] += _num(row["passing_yards"])
        t["pass_tds"] += _num(row["passing_tds"])
        t["interceptions"] += _num(row["passing_interceptions"])
        t["rush_yards"] += _num(row["rushing_yards"])
        t["rush_tds"] += _num(row["rushing_tds"])
    return [
        QbLine(franchise, season, player, int(t["attempts"]), int(t["completions"]),
               t["pass_yards"], int(t["pass_tds"]), int(t["interceptions"]),
               t["rush_yards"], int(t["rush_tds"]))
        for (franchise, season, player), t in sorted(totals.items())
    ]


def team_seasons_from_games(game_rows, franchise_codes, first_season, last_season):
    """nflverse's games file -> one TeamSeason per franchise per season.

    A game with no score yet is not a game. Two nflverse codes for one franchise
    (Oakland and Las Vegas) are one team, through `franchise_codes`.
    """
    record = defaultdict(lambda: [0, 0, 0])
    reached = defaultdict(int)      # furthest round played, 1..4
    won_title = set()
    for row in game_rows:
        season = int(row["season"])
        if not first_season <= season <= last_season:
            continue
        if row["home_score"].strip() == "" or row["away_score"].strip() == "":
            continue
        home = (franchise_codes[row["home_team"]], season)
        away = (franchise_codes[row["away_team"]], season)
        home_score, away_score = float(row["home_score"]), float(row["away_score"])
        kind = row["game_type"]
        record[home], record[away]      # a team exists once it has played
        if kind == "REG":
            if home_score == away_score:
                record[home][2] += 1
                record[away][2] += 1
            elif home_score > away_score:
                record[home][0] += 1
                record[away][1] += 1
            else:
                record[home][1] += 1
                record[away][0] += 1
        elif kind in ROUNDS:
            depth = ROUNDS.index(kind) + 1
            for side in (home, away):
                reached[side] = max(reached[side], depth)
            if kind == "SB":
                won_title.add(home if home_score > away_score else away)
    return [
        TeamSeason(franchise, season, w, l, t,
                   reached[(franchise, season)] + ((franchise, season) in won_title))
        for (franchise, season), (w, l, t) in sorted(record.items(), key=lambda kv: (kv[0][1], kv[0][0]))
    ]


# ------------------------------------------------------------- real seasons --


def real_seasons(rated, lines, teams, awards):
    """Join the ratings pipeline's rows to what each quarterback and team did.

    Every rated season must have a stat line and a team result, and every award
    must name a rated player-season: the join is what the whole fit stands on,
    and a row dropped quietly would skew it without anyone seeing.

    An award belongs to a player-season, which is two rows when a quarterback
    threw for two teams; it is attached to the one with the bigger workload, so
    it is counted once.
    """
    line_of = {(l.franchise_code, l.season, l.player_id): l for l in lines}
    team_of = {(t.franchise_code, t.season): t for t in teams}

    for a in awards:
        if a.award not in AWARDS:
            raise ValueError(f"unknown award {a.award!r}")

    biggest = {}
    for r in rated:
        line = line_of.get((r.franchise_code, r.season, r.player_id))
        if line is None:
            raise ValueError(f"no stat line for {r.display_name} ({r.player_id}) "
                             f"{r.season} with {r.franchise_code}")
        best = biggest.get((r.season, r.player_id))
        if best is None or line.attempts > best[0]:
            biggest[(r.season, r.player_id)] = (line.attempts, r.franchise_code)

    awarded = defaultdict(set)
    for a in awards:
        if (a.season, a.player_id) not in biggest:
            raise ValueError(f"award {a.award!r} {a.season} names {a.player_id}, "
                             "who has no rated season that year")
        awarded[(a.season, a.player_id, biggest[(a.season, a.player_id)][1])].add(a.award)

    out = []
    for r in rated:
        line = line_of[(r.franchise_code, r.season, r.player_id)]
        t = team_of.get((r.franchise_code, r.season))
        if t is None:
            raise ValueError(f"no team result for {r.franchise_code} {r.season}")
        out.append(RealSeason(
            r.franchise_code, r.season, r.player_id, r.display_name,
            r.accuracy, r.arm_talent, r.mobility, r.iq, r.build, r.supporting_cast,
            line.attempts, line.completions, line.pass_yards, line.pass_tds,
            line.interceptions, line.rush_yards, line.rush_tds,
            t.wins, t.losses, t.ties, t.playoff_depth,
            frozenset(awarded.get((r.season, r.player_id, r.franchise_code), ())),
        ))
    out.sort(key=lambda s: (s.season, s.franchise_code, s.player_id))
    return out


# ----------------------------------------------------------------- the lines --


def scaled_wins(wins, losses, ties, season_games):
    """Wins per full season: a tie is half a win, and a short schedule is scaled up."""
    return season_games * (wins + 0.5 * ties) / (wins + losses + ties)


def season_line(s, config):
    """A real season's fitted outputs, per full season.

    Counting stats and wins are scaled to `season_games` (by the team's games
    played, so a quarterback who missed time still shows it); rates are not.
    """
    games = s.wins + s.losses + s.ties
    scale = config.season_games / games
    return {
        "attempts": s.attempts * scale,
        "comp_pct": s.completions / s.attempts,
        "ypa": s.pass_yards / s.attempts,
        "td_rate": s.pass_tds / s.attempts,
        "int_rate": s.interceptions / s.attempts,
        "rush_yards": s.rush_yards * scale,
        "rush_td": s.rush_tds * scale,
        "wins": scaled_wins(s.wins, s.losses, s.ties, config.season_games),
    }


# -------------------------------------------------------------------- links --


def _to_link(spec, y, config):
    if spec.link == "identity":
        return y
    if spec.link == "log":
        return math.log(max(y, config.log_floor))
    if spec.link == "logit":
        p = (y - spec.low) / (spec.high - spec.low)
        p = min(max(p, config.logit_margin), 1 - config.logit_margin)
        return math.log(p / (1 - p))
    raise ValueError(f"unknown link {spec.link!r}")


def _from_link(spec, z):
    if spec.link == "identity":
        return min(max(z, spec.low), spec.high)
    if spec.link == "log":
        return min(math.exp(min(z, 700)), spec.high)
    if spec.link == "logit":
        return spec.low + (spec.high - spec.low) * sigmoid(z)
    raise ValueError(f"unknown link {spec.link!r}")


# -------------------------------------------------------------- linear algebra --


def _solve(matrix, rhs):
    """Solve matrix @ x = rhs by Gaussian elimination with partial pivoting."""
    n = len(rhs)
    a = [list(row) + [rhs[i]] for i, row in enumerate(matrix)]
    for col in range(n):
        pivot = max(range(col, n), key=lambda r: abs(a[r][col]))
        if abs(a[pivot][col]) < 1e-12:
            raise ValueError("the six values do not vary independently enough to fit")
        a[col], a[pivot] = a[pivot], a[col]
        for r in range(col + 1, n):
            factor = a[r][col] / a[col][col]
            for c in range(col, n + 1):
                a[r][c] -= factor * a[col][c]
    x = [0.0] * n
    for r in range(n - 1, -1, -1):
        x[r] = (a[r][n] - sum(a[r][c] * x[c] for c in range(r + 1, n))) / a[r][r]
    return x


def _least_squares(rows, ys, ridge=0.0, penalised=None):
    """Least squares of ys on rows, with an intercept first.

    With `ridge` > 0 the slopes are penalised: the columns are standardised, the
    penalty `ridge * n` is added to each slope's diagonal, and the result is
    converted back to the raw values, so the coefficients read the same way and
    the intercept is unpenalised. Values that move together then share credit
    instead of one taking it all. `penalised` is the column indexes it applies to
    (None: all). `ridge` 0 is exactly ordinary least squares.
    """
    if ridge > 0:
        return _ridge_least_squares(rows, ys, ridge, penalised)
    design = [[1.0] + [float(v) for v in row] for row in rows]
    k = len(design[0])
    xtx = [[sum(r[i] * r[j] for r in design) for j in range(k)] for i in range(k)]
    xty = [sum(r[i] * y for r, y in zip(design, ys)) for i in range(k)]
    beta = _solve(xtx, xty)
    residuals = [y - sum(b * x for b, x in zip(beta, r)) for r, y in zip(design, ys)]
    return beta, residuals


def _ridge_least_squares(rows, ys, ridge, penalised=None):
    n, k = len(rows), len(rows[0])
    penalised = set(range(k)) if penalised is None else set(penalised)
    means = [sum(float(r[j]) for r in rows) / n for j in range(k)]
    sds = [_population_sd([float(r[j]) for r in rows]) for j in range(k)]
    if any(sd < 1e-12 for sd in sds):
        raise ValueError("a value never varies, so a ridge cannot standardise it")
    z = [[(float(r[j]) - means[j]) / sds[j] for j in range(k)] for r in rows]
    y_mean = sum(ys) / n
    ztz = [[sum(r[i] * r[j] for r in z) + (ridge * n if i == j and i in penalised else 0.0) for j in range(k)]
           for i in range(k)]
    zty = [sum(r[i] * (y - y_mean) for r, y in zip(z, ys)) for i in range(k)]
    slopes = [b / sd for b, sd in zip(_solve(ztz, zty), sds)]
    intercept = y_mean - sum(b * m for b, m in zip(slopes, means))
    beta = [intercept] + slopes
    residuals = [y - intercept - sum(b * float(v) for b, v in zip(slopes, r))
                 for r, y in zip(rows, ys)]
    return beta, residuals


def quantile(sorted_values, p):
    """The p-quantile of an already sorted list, by linear interpolation."""
    if len(sorted_values) == 1:
        return sorted_values[0]
    position = p * (len(sorted_values) - 1)
    lower = int(math.floor(position))
    upper = min(lower + 1, len(sorted_values) - 1)
    fraction = position - lower
    # Written as a step from the lower value, so two equal neighbours give exactly
    # that value and a table of quantiles never wobbles a hair backwards.
    return sorted_values[lower] + (sorted_values[upper] - sorted_values[lower]) * fraction


def _grid(points):
    if points < 2:
        raise ValueError("a quantile table needs at least two points")
    return [i / (points - 1) for i in range(points)]


# ----------------------------------------------------------------- the model --


class OutputFit(NamedTuple):
    """One output's fitted formula: link(y) = intercept + sum(coefficient * value)."""

    name: str
    spec: OutputSpec
    intercept: float
    coefficients: tuple         # in SLOTS order
    residual_sd: float          # the regression's standard error, in link units
    residuals: tuple            # ((p, residual), ...) the real spread, in link units
    r_squared: float            # the share of the real spread the formula explains


class LadderRung(NamedTuple):
    """P(clear this rung | reached it) = sigmoid(intercept + slope * wins)."""

    step: str
    intercept: float
    slope: float


class Norm(NamedTuple):
    """The mean and spread of a metric across the real seasons."""

    metric: str
    mean: float
    sd: float


class Formula(NamedTuple):
    """One term of a named weighted sum.

    `score`: over the score components. `stat_line`, `team_success` and each
    `award_<name>`: a weight on a z-scored metric. `awards`: points per award.
    """

    name: str
    term: str
    weight: float


class AwardThreshold(NamedTuple):
    award: str
    threshold: float    # award score at or above which the award is earned
    spread: float       # sd of the real winners' scores; noise near the edge scales by it
    noise_scale: float
    winners: int        # how many real seasons the threshold was calibrated on
    requires: str = ""  # the award a season must also earn ("" for none)


class SeasonModel(NamedTuple):
    outputs: tuple              # OutputFit, by name
    ladder: tuple               # LadderRung, in LADDER_STEPS order
    norms: tuple                # Norm, in METRICS order
    formulas: tuple             # Formula, by (name, term)
    awards: tuple               # AwardThreshold, in AWARDS order
    distributions: Mapping      # component -> ((p, composite), ...) over the real seasons


def _sorted(seasons):
    return sorted(seasons, key=lambda s: (s.season, s.franchise_code, s.player_id))


def _population_sd(values):
    mean = sum(values) / len(values)
    return math.sqrt(sum((v - mean) ** 2 for v in values) / len(values))


def values_of(s):
    return tuple(getattr(s, slot) for slot in SLOTS)


# ------------------------------------------------------------ the formulas --


def _trimmed_fit(rows, ys, full, spec, penalised):
    """Hold each trimmed value at its factor of the full fit and refit the rest."""
    held = {SLOTS.index(slot): full[1 + SLOTS.index(slot)] * factor for slot, factor in spec.trim}
    kept = [i for i in range(len(SLOTS)) if i not in held]
    adjusted = [y - sum(c * float(row[i]) for i, c in held.items()) for y, row in zip(ys, rows)]
    inner = None if penalised is None else [kept.index(i) for i in penalised if i in kept]
    beta_kept, _ = _least_squares([[row[i] for i in kept] for row in rows], adjusted, spec.ridge, inner)
    beta = [beta_kept[0]] + [held[i] if i in held else beta_kept[1 + kept.index(i)]
                             for i in range(len(SLOTS))]
    residuals = [y - beta[0] - sum(b * float(v) for b, v in zip(beta[1:], row))
                 for y, row in zip(ys, rows)]
    return beta, residuals


def _fit_output(name, spec, seasons, config):
    ys = [_to_link(spec, season_line(s, config)[name], config) for s in seasons]
    penalised = [SLOTS.index(slot) for slot in spec.ridge_slots] if spec.ridge_slots else None
    rows = [values_of(s) for s in seasons]
    beta, residuals = _least_squares(rows, ys, spec.ridge, penalised)
    if spec.trim:
        beta, residuals = _trimmed_fit(rows, ys, beta, spec, penalised)
    n, k = len(seasons), len(beta)
    sd = math.sqrt(sum(r * r for r in residuals) / (n - k)) if n > k else 0.0
    ordered = sorted(residuals)
    table = tuple((p, quantile(ordered, p)) for p in _grid(config.residual_points))
    mean = sum(ys) / n
    total = sum((y - mean) ** 2 for y in ys)
    r_squared = 1 - sum(r * r for r in residuals) / total if total > 1e-12 else 0.0
    return OutputFit(name, spec, beta[0], tuple(beta[1:]), sd, table, r_squared)


def fit_outputs(seasons, config):
    """The fitted formula for each configured output, by name."""
    for name in config.outputs:
        if name not in LINE_OUTPUTS:
            raise ValueError(f"unknown output {name!r}; expected one of {LINE_OUTPUTS}")
    seasons = _sorted(seasons)
    if len(seasons) <= len(SLOTS) + 1:
        raise ValueError(f"{len(seasons)} seasons cannot fit {len(SLOTS) + 1} terms")
    return tuple(_fit_output(name, config.outputs[name], seasons, config)
                 for name in sorted(config.outputs))


def predict(outputs, values, draws=None):
    """The season for six values in SLOTS order: {output: value}.

    With no `draws` it is the expected season. `draws` maps an output to a number
    u in [0, 1] (in a game, from the run's seed), and that output is then moved by
    its noise: the real residual at quantile u, interpolated from its table and
    scaled by the output's `noise_scale`, added on the link scale before the
    inverse link. So noise is bounded by the real extremes at u = 0 and u = 1.
    """
    draws = draws or {}
    out = {}
    for o in outputs:
        z = o.intercept + sum(c * v for c, v in zip(o.coefficients, values))
        if o.name in draws:
            z += o.spec.noise_scale * quantile([r for _, r in o.residuals], draws[o.name])
        out[o.name] = _from_link(o.spec, z)
    return out


def expected_metrics(outputs, values, draws=None):
    """The expected season's metrics: the fitted outputs turned into a line.

    Needs every output in LINE_OUTPUTS. `playoff_depth` is not here: it comes
    from the ladder (`expected_depth`) or from the season that was actually
    played.
    """
    e = predict(outputs, values, draws)
    return {
        "pass_yards": e["attempts"] * e["ypa"],
        "pass_td": e["attempts"] * e["td_rate"],
        "interceptions": e["attempts"] * e["int_rate"],
        "rating": passer_rating(e["comp_pct"], 1.0, e["ypa"], e["td_rate"], e["int_rate"]),
        "rush_yards": e["rush_yards"],
        "rush_td": e["rush_td"],
        "wins": e["wins"],
    }


# ------------------------------------------------------------ playoff ladder --


def sigmoid(z):
    return 1 / (1 + math.exp(-z)) if z >= 0 else math.exp(z) / (1 + math.exp(z))


def _logistic(xs, ys, ridge):
    """(intercept, slope) of P(y) = sigmoid(intercept + slope * x), with an L2
    penalty on the slope, by Newton's method. The slope is never negative."""
    n = len(xs)
    rate = sum(ys) / n
    if rate in (0.0, 1.0):
        # Nothing to separate: a rung everyone cleared or no one did.
        return (12.0 if rate else -12.0), 0.0
    mean_x = sum(xs) / n
    cx = [x - mean_x for x in xs]
    a, b = math.log(rate / (1 - rate)), 0.0
    for _ in range(100):
        ps = [sigmoid(a + b * x) for x in cx]
        g_a = sum(y - p for y, p in zip(ys, ps))
        g_b = sum((y - p) * x for y, p, x in zip(ys, ps, cx)) - ridge * b
        w = [p * (1 - p) for p in ps]
        h_aa = sum(w)
        h_ab = sum(wi * x for wi, x in zip(w, cx))
        h_bb = sum(wi * x * x for wi, x in zip(w, cx)) + ridge
        det = h_aa * h_bb - h_ab * h_ab
        if det <= 0:
            break
        step_a = (g_a * h_bb - g_b * h_ab) / det
        step_b = (g_b * h_aa - g_a * h_ab) / det
        a, b = a + step_a, b + step_b
        if abs(step_a) < 1e-10 and abs(step_b) < 1e-10:
            break
    if b < 0:
        # Chance noise: more wins is never worse. Hold it flat at the base rate.
        return math.log(rate / (1 - rate)), 0.0
    return a - b * mean_x, b


def fit_ladder(teams, config):
    """The chance of each playoff rung as a function of wins, over every team.

    Each rung is fitted on the teams that reached it: making the playoffs, then
    reaching the divisional round (a bye counts), the conference game, the Super
    Bowl, and winning it. All teams, not only those with a rated quarterback,
    because the ladder is about how wins turn into playoffs.
    """
    teams = sorted(teams, key=lambda t: (t.season, t.franchise_code))
    out = []
    for k, step in enumerate(LADDER_STEPS):
        eligible = [t for t in teams if t.playoff_depth >= k]
        if not eligible:
            raise ValueError(f"no team reached the rung before {step}: nothing to fit")
        xs = [scaled_wins(t.wins, t.losses, t.ties, config.season_games) for t in eligible]
        ys = [1.0 if t.playoff_depth >= k + 1 else 0.0 for t in eligible]
        intercept, slope = _logistic(xs, ys, config.ladder_ridge)
        out.append(LadderRung(step, intercept, slope))
    return tuple(out)


def expected_depth(ladder, wins):
    """The average playoff depth of a team with this many wins."""
    survive, total = 1.0, 0.0
    for rung in ladder:
        survive *= sigmoid(rung.intercept + rung.slope * wins)
        total += survive
    return total


# ---------------------------------------------------------- metrics and norms --


def season_metrics(s, config):
    """A real season's metrics, per full season."""
    line = season_line(s, config)
    return {
        "pass_yards": line["attempts"] * line["ypa"],
        "pass_td": line["attempts"] * line["td_rate"],
        "interceptions": line["attempts"] * line["int_rate"],
        "rating": passer_rating(s.completions, s.attempts, s.pass_yards, s.pass_tds, s.interceptions),
        "rush_yards": line["rush_yards"],
        "rush_td": line["rush_td"],
        "wins": line["wins"],
        "playoff_depth": float(s.playoff_depth),
    }


def fit_norms(seasons, config):
    """The mean and spread of every metric over the real seasons.

    A metric that never varies has an sd of 1, so it z-scores to zero and adds
    nothing instead of dividing by zero.
    """
    seasons = _sorted(seasons)
    rows = [season_metrics(s, config) for s in seasons]
    out = []
    for metric in METRICS:
        values = [r[metric] for r in rows]
        sd = _population_sd(values)
        out.append(Norm(metric, sum(values) / len(values), sd if sd > 0 else 1.0))
    return tuple(out)


def fit_formulas(config):
    """Every weighted sum the score and the awards are made of, as rows."""
    if sorted(config.score_weights) != sorted(SCORE_COMPONENTS):
        raise ValueError(f"score_weights must name exactly {SCORE_COMPONENTS}")
    rows = [Formula("score", c, w) for c, w in config.score_weights.items()]
    sums = {"stat_line": config.stat_line_weights, "team_success": config.team_success_weights}
    for a in AWARDS:
        if a not in config.award_terms:
            raise ValueError(f"no score terms configured for award {a!r}")
        sums[f"award_{a}"] = config.award_terms[a]
    for name, weights in sums.items():
        for metric, w in weights.items():
            if metric not in METRICS:
                raise ValueError(f"{name}: unknown metric {metric!r}; expected one of {METRICS}")
            rows.append(Formula(name, metric, w))
    for award, points in config.award_points.items():
        if award not in AWARDS:
            raise ValueError(f"award points for unknown award {award!r}")
        rows.append(Formula("awards", award, points))
    return tuple(sorted(rows))


def composite(model, name, metrics, awards=()):
    """A named formula's value for a season's metrics (and, for `awards`, its awards)."""
    terms = {f.term: f.weight for f in model.formulas if f.name == name}
    if name == "awards":
        return sum(terms.get(a, 0.0) for a in awards)
    norms = {n.metric: n for n in model.norms}
    return sum(w * (metrics[t] - norms[t].mean) / norms[t].sd for t, w in terms.items())


def percentile_of(table, x):
    """The share of a quantile table's values strictly below x, 0 to 1.

    "Better than X% of real seasons": a tie is not better, so a season with no
    awards, like most real ones, is better than none of them, and one above the
    whole table is exactly 1.
    """
    return sum(1 for _, v in table if v < x) / len(table)


def score(model, metrics, awards=()):
    """The 0-100 score of a season: its stat line, team success and awards, each
    ranked against the real seasons, mixed by the configured weights."""
    weights = {f.term: f.weight for f in model.formulas if f.name == "score"}
    total = sum(weights.values())
    mixed = sum(
        w * percentile_of(model.distributions[c], composite(model, c, metrics, awards))
        for c, w in weights.items())
    return 100.0 * mixed / total


def fit_distributions(seasons, norms, formulas, config):
    """How the real seasons spread on each score component: a quantile table each."""
    seasons = _sorted(seasons)
    shell = SeasonModel((), (), tuple(norms), tuple(formulas), (), {})
    grid = _grid(config.distribution_points)
    out = {}
    for component in SCORE_COMPONENTS:
        values = sorted(composite(shell, component, season_metrics(s, config), s.awards)
                        for s in seasons)
        out[component] = tuple((p, quantile(values, p)) for p in grid)
    return out


# -------------------------------------------------------------- award thresholds --


def fit_awards(seasons, norms, config):
    """One threshold per award, calibrated on the real winners' stat lines and records.

    A season's award score is its weighted z-scored metrics; the threshold is the
    configured quantile of the winners' scores, so 0 lets in a season as good as
    the weakest real winner and 1 asks for the best. Each award needs at least one
    real winner to calibrate on.
    """
    seasons = _sorted(seasons)
    shell = SeasonModel((), (), tuple(norms), fit_formulas(config), (), {})
    requires = dict(config.award_requires or {})
    for award, needed in requires.items():
        if award not in AWARDS or needed not in AWARDS or award == needed:
            raise ValueError(f"award_requires: {award!r} -> {needed!r} is not a pair of different awards")
    out = []
    for award in AWARDS:
        if award not in config.award_quantile or award not in config.award_noise_scale:
            raise ValueError(f"no threshold quantile or noise scale configured for award {award!r}")
        scores = sorted(composite(shell, f"award_{award}", season_metrics(s, config))
                        for s in seasons if award in s.awards)
        if not scores:
            raise ValueError(f"no real season won {award!r}: nothing to calibrate on")
        mean = sum(scores) / len(scores)
        spread = math.sqrt(sum((x - mean) ** 2 for x in scores) / len(scores))
        out.append(AwardThreshold(award, quantile(scores, config.award_quantile[award]),
                                  spread, config.award_noise_scale[award], len(scores),
                                  requires.get(award, "")))
    return tuple(out)


def earns(model, award, metrics):
    """Whether a season's metrics earn the award (before any noise): they clear its
    threshold and, if it requires another award, earn that one too."""
    (found,) = [a for a in model.awards if a.award == award]
    return (composite(model, f"award_{award}", metrics) >= found.threshold
            and (not found.requires or earns(model, found.requires, metrics)))


# --------------------------------------------------------------------- the fit --


def fit(seasons, teams, config):
    """Real seasons + every team's results + tuning -> the season model."""
    seasons = _sorted(seasons)
    norms = fit_norms(seasons, config)
    formulas = fit_formulas(config)
    return SeasonModel(
        outputs=fit_outputs(seasons, config),
        ladder=fit_ladder(teams, config),
        norms=norms,
        formulas=formulas,
        awards=fit_awards(seasons, norms, config),
        distributions=fit_distributions(seasons, norms, formulas, config),
    )
