"""Source rows + tuning -> QB Season Builder's finished rating values.

This module is the one seam in the ratings build: parsed source rows and a
`Config` in, finished values (0-99) out — five quality values per qualifying
quarterback-season and one Supporting Cast value per team-season. Everything
that can be quietly wrong lives here: the qualifying cutoff, the within-season
ranking, the Madden/season blend, the edition fallback, the cast blend and the
hand overrides. Fetching, guards and artifact writing stay outside it.

It is a pure function. No network, no filesystem, no clock, and no constants a
caller cannot replace: every weight, band and threshold arrives in `Config`,
which is how the tests can pass their own tuning and how the real numbers can
be retuned without touching this file.

The rating recipe (issue #72, "Ratings"):

1. Each of a trait's two inputs — a talent value from the private Madden
   ratings, and a season value from our own stat formulas — is built from a few
   components. Every component is ranked *within its season* (0 = worst
   qualifying quarterback that year, 1 = best), the components are averaged by
   their configured weights, and that average is ranked within its season once
   more. Ranking first is what lets two numbers on different scales, and from
   different eras, be blended at all.
2. The two ranks are blended by the trait's (Madden, stats) weights and mapped
   onto the configured value band.
3. Where a quarterback has no usable Madden input for a trait, that row is 100%
   the stat side; the hand overrides table covers whatever still comes out
   clearly wrong.
"""

from collections import defaultdict
from typing import Mapping, NamedTuple, Optional

# The five quarterback qualities a pick can take, plus the sixth slot.
TRAITS = ("accuracy", "arm_talent", "mobility", "iq", "build")
CAST = "supporting_cast"


class Config(NamedTuple):
    """Every tuning input. Nothing in this module reads a constant instead."""

    # A quarterback-season qualifies with at least this many pass attempts for
    # one team ("roughly 150" in the spec). Mid-season replacements clear it,
    # one-start rookie years do not.
    min_attempts: int
    # slot (a trait or CAST) -> (madden weight, stats weight). Any two
    # non-negative numbers; only their ratio matters.
    weights: Mapping[str, tuple]
    # The value a season's worst / best ranked row maps to. Values are clamped
    # to 0-99, which is what the schema accepts.
    value_floor: float
    value_ceiling: float
    # trait -> {Madden attribute: weight}. Attributes are the dataset's own
    # column names ("overall" included); a missing one drops out of that row's
    # average rather than counting as zero.
    madden_attrs: Mapping[str, Mapping[str, float]]
    # trait -> {stat metric: weight}. Metric names are METRICS' keys.
    stat_metrics: Mapping[str, Mapping[str, float]]
    # metric -> prior denominator. A small-sample rate is pulled toward that
    # season's league rate as if it had this many more observations (attempts,
    # carries, ...). A metric not listed is not shrunk.
    shrinkage: Mapping[str, float]
    # The Supporting Cast: offense's share of the blend (defense gets the rest),
    # per PFR slot category (unit, how many top players count, weight within
    # its unit), and which Madden attribute rates a player there.
    cast_offense_share: float
    cast_slots: Mapping[str, tuple]
    cast_attr: str


# ------------------------------------------------------------------ inputs --


class QbSeason(NamedTuple):
    """One quarterback's regular season with one team, as season totals."""

    franchise_code: str
    season: int
    player_id: str          # Pro Football Reference id, the same key the AV pool uses
    display_name: str
    games: int              # regular-season games in which he threw a pass
    team_games: int         # regular-season games his team played
    attempts: int
    completions: int
    pass_yards: float
    air_yards: float
    explosive: int          # completions of 20+ yards
    cpoe_sum: float         # weekly CPOE weighted by that week's attempts
    pass_epa: float         # passing EPA, sacks included (nflverse's qb_epa)
    interceptions: int
    sacks: int
    fumbles_lost: int
    carries: int
    rush_yards: float
    rush_first_downs: int
    rush_epa: float
    height: Optional[float]  # inches
    weight: Optional[float]  # pounds

    @property
    def dropbacks(self):
        return self.attempts + self.sacks


class MaddenRating(NamedTuple):
    """One player's row from one edition of the private ratings source.

    `edition` is the dataset's own season key: the edition released in August of
    that season, i.e. the *pre-season* edition for that season. `ratings` is
    sparse — an attribute the edition does not have is absent, not zero.
    """

    edition: int
    player_id: str          # Pro Football Reference id
    position: str
    ratings: Mapping[str, float]
    team: str = ""          # the edition's own team code for him, pre-season


class RosterPlayer(NamedTuple):
    """One player on one franchise's roster in one season, with his AV."""

    franchise_code: str
    season: int
    player_id: str
    slot_category: str      # QB / RB / WR / TE / OL / DL / LB / CB / S / ST
    av: Optional[float]     # None where the source has no AV for the season


class Override(NamedTuple):
    """A hand correction. `player_id` is '' for a Supporting Cast override."""

    franchise_code: str
    season: int
    player_id: str
    slot: str
    value: int
    reason: str = ""


class Expectation(NamedTuple):
    """A known-quarterback sanity check on a finished value.

    `player_id` '' targets a team's Supporting Cast. `franchise_code` '' means
    any team the player threw for that season.
    """

    player_id: str
    season: int
    slot: str
    low: int
    high: int
    franchise_code: str = ""
    note: str = ""


# ----------------------------------------------------------------- outputs --


class QbRatingRow(NamedTuple):
    """One row of `qb_season_builder_private.qb_seasons`, in column order."""

    franchise_code: str
    season: int
    player_id: str
    display_name: str
    accuracy: int
    arm_talent: int
    mobility: int
    iq: int
    build: int


class TeamRatingRow(NamedTuple):
    """One row of `qb_season_builder_private.team_seasons`, in column order."""

    franchise_code: str
    season: int
    supporting_cast: int


class Ratings(NamedTuple):
    qb_rows: list
    team_rows: list


# ------------------------------------------------------------- stat metrics --

# Each metric is numerator / denominator over a QbSeason's fields (or a derived
# property), plus which direction is better. Height, weight and durability are
# not ratios of counting stats, so they are handled by name in `_direct_metric`.
class _Ratio(NamedTuple):
    num: str
    den: str
    higher_is_better: bool


METRICS = {
    "comp_pct": _Ratio("completions", "attempts", True),
    "cpoe": _Ratio("cpoe_sum", "attempts", True),
    "air_yards_per_att": _Ratio("air_yards", "attempts", True),
    "explosive_rate": _Ratio("explosive", "attempts", True),
    "epa_per_dropback": _Ratio("pass_epa", "dropbacks", True),
    "int_rate": _Ratio("interceptions", "dropbacks", False),
    "sack_rate": _Ratio("sacks", "dropbacks", False),
    "fumble_rate": _Ratio("fumbles_lost", "dropbacks", False),
    "rush_ypc": _Ratio("rush_yards", "carries", True),
    "rush_fd_rate": _Ratio("rush_first_downs", "carries", True),
    "rush_epa_per_game": _Ratio("rush_epa", "games", True),
}
DIRECT_METRICS = ("height", "weight", "durability")


# ---------------------------------------------------------------- aggregate --


def _num(value):
    """A weekly-stats cell as a float; blank and 'NA' are zero."""
    if value is None:
        return 0.0
    value = value.strip()
    if value in ("", "NA"):
        return 0.0
    return float(value)


def qb_seasons_from_weeks(week_rows, people, franchise_codes, min_attempts):
    """nflverse weekly rows -> one QbSeason per qualifying (quarterback, team, season).

    `week_rows` are `csv.DictReader` dicts over `stats_player_week_{season}.csv`
    in its own columns, for every player (team games are counted off all of
    them). `people` maps a GSIS id to `(pfr_id, display_name, height, weight)`.
    `franchise_codes` maps nflverse's team codes onto Pro Football Reference's
    stable franchise codes. A quarterback who qualifies with two teams in one
    season is two rows, as the schema keys them.

    An id the source cannot resolve raises rather than being dropped: a
    quarterback silently missing from the pool is worse than a failed build.
    """
    team_weeks = defaultdict(set)
    totals = {}
    for row in week_rows:
        if row["season_type"] != "REG":
            continue
        season = int(row["season"])
        team_weeks[(row["team"], season)].add(int(row["week"]))
        if row["position"] != "QB" or _num(row["attempts"]) <= 0:
            continue

        key = (row["team"], season, row["player_id"])
        t = totals.setdefault(key, defaultdict(float))
        t["games"] += 1
        t["attempts"] += _num(row["attempts"])
        t["completions"] += _num(row["completions"])
        t["pass_yards"] += _num(row["passing_yards"])
        t["air_yards"] += _num(row["passing_air_yards"])
        t["explosive"] += _num(row["passing_20"])
        t["cpoe_sum"] += _num(row["passing_cpoe"]) * _num(row["attempts"])
        t["pass_epa"] += _num(row["passing_epa"])
        t["interceptions"] += _num(row["passing_interceptions"])
        t["sacks"] += _num(row["sacks_suffered"])
        t["fumbles_lost"] += _num(row["sack_fumbles_lost"]) + _num(row["rushing_fumbles_lost"])
        t["carries"] += _num(row["carries"])
        t["rush_yards"] += _num(row["rushing_yards"])
        t["rush_first_downs"] += _num(row["rushing_first_downs"])
        t["rush_epa"] += _num(row["rushing_epa"])

    out = []
    for (team, season, gsis), t in totals.items():
        if t["attempts"] < min_attempts:
            continue
        if team not in franchise_codes:
            raise ValueError(f"no franchise code for nflverse team {team!r}")
        if gsis not in people:
            raise ValueError(f"no Pro Football Reference id for {gsis}")
        pfr_id, name, height, weight = people[gsis]
        out.append(QbSeason(
            franchise_code=franchise_codes[team],
            season=season,
            player_id=pfr_id,
            display_name=name,
            games=int(t["games"]),
            team_games=len(team_weeks[(team, season)]),
            attempts=int(t["attempts"]),
            completions=int(t["completions"]),
            pass_yards=t["pass_yards"],
            air_yards=t["air_yards"],
            explosive=int(t["explosive"]),
            cpoe_sum=t["cpoe_sum"],
            pass_epa=t["pass_epa"],
            interceptions=int(t["interceptions"]),
            sacks=int(t["sacks"]),
            fumbles_lost=int(t["fumbles_lost"]),
            carries=int(t["carries"]),
            rush_yards=t["rush_yards"],
            rush_first_downs=int(t["rush_first_downs"]),
            rush_epa=t["rush_epa"],
            height=height,
            weight=weight,
        ))
    out.sort(key=lambda q: (q.season, q.franchise_code, q.player_id))
    return out


# ------------------------------------------------------------------ ranking --


def percentiles(values):
    """{key: value} -> {key: 0..1}, the value's rank within the group.

    Ties share their average rank, so equal inputs get equal outputs and the
    result does not depend on the order the keys arrive in. One value ranks at
    the middle: a lone row has nothing to be better or worse than.
    """
    n = len(values)
    if n == 0:
        return {}
    if n == 1:
        return {key: 0.5 for key in values}
    ordered = sorted(values.items(), key=lambda kv: (kv[1], kv[0]))
    out = {}
    i = 0
    while i < n:
        j = i
        while j + 1 < n and ordered[j + 1][1] == ordered[i][1]:
            j += 1
        rank = (i + j) / 2 / (n - 1)
        for k in range(i, j + 1):
            out[ordered[k][0]] = rank
        i = j + 1
    return out


def _composite(component_ranks, weights):
    """Weighted mean of per-component ranks, over the components a row has.

    `component_ranks` is {component: {key: rank}}. Returns {key: mean}; a key
    with no component at all is absent, and one missing some is averaged over
    what it has rather than penalised.
    """
    num = defaultdict(float)
    den = defaultdict(float)
    for component, weight in weights.items():
        for key, rank in component_ranks.get(component, {}).items():
            num[key] += weight * rank
            den[key] += weight
    return {key: num[key] / den[key] for key in num if den[key] > 0}


def _rank_composite(component_ranks, weights):
    return percentiles(_composite(component_ranks, weights))


def _blend(p_madden, p_stats, weights):
    """Blend the two ranks; a missing Madden input is 100% the stat side."""
    w_madden, w_stats = weights
    if p_madden is None or w_madden <= 0:
        return p_stats
    if p_stats is None or w_stats <= 0:
        return p_madden
    return (w_madden * p_madden + w_stats * p_stats) / (w_madden + w_stats)


def _to_value(p, config):
    value = config.value_floor + (config.value_ceiling - config.value_floor) * p
    return max(0, min(99, int(value + 0.5)))


# --------------------------------------------------------------- QB ratings --


def _index_madden(madden):
    return {(m.edition, m.player_id): m for m in madden}


def _madden_row(index, player_id, season, has):
    """The Madden row that rates this player's `season`.

    The edition released *after* a season rates it (edition key season+1), which
    corrects rookie and breakout cases; the pre-season edition (key season) is
    the fallback for a player the later one does not rate. `has` says what
    "rates it" means for the caller — the trait's attributes, or an overall —
    so a later edition that lists the player without the attribute the trait
    needs falls back too, instead of leaving a hole.
    """
    for edition in (season + 1, season):
        row = index.get((edition, player_id))
        if row is not None and has(row.ratings):
            return row
    return None


def _direct_metric(name, q):
    """A metric that is a measurement, not a ratio of counting stats."""
    if name == "height":
        return q.height
    if name == "weight":
        return q.weight
    if name == "durability":
        return q.games / q.team_games if q.team_games else None
    raise KeyError(name)


def _stat_component_ranks(season_rows, config, names):
    """{metric: {row index: rank}} for one season, direction and shrinkage applied."""
    out = {}
    for name in names:
        if name in DIRECT_METRICS:
            raw = {i: _direct_metric(name, q) for i, q in enumerate(season_rows)}
            out[name] = percentiles({i: v for i, v in raw.items() if v is not None})
            continue

        m = METRICS[name]
        pairs = {i: (getattr(q, m.num), getattr(q, m.den)) for i, q in enumerate(season_rows)}
        league_num = sum(n for n, _ in pairs.values())
        league_den = sum(d for _, d in pairs.values())
        league_rate = league_num / league_den if league_den else 0.0
        prior = config.shrinkage.get(name, 0.0)
        values = {}
        for i, (num, den) in pairs.items():
            if den + prior <= 0:
                continue
            rate = (num + prior * league_rate) / (den + prior)
            values[i] = rate if m.higher_is_better else -rate
        out[name] = percentiles(values)
    return out


def _qb_season_ranks(season_rows, index, season, config):
    """For one season: {trait: {row index: blended 0..1 rank}}."""
    stat_names = sorted({n for t in TRAITS for n in config.stat_metrics.get(t, {})})
    stat_ranks = _stat_component_ranks(season_rows, config, stat_names)

    out = {}
    for trait in TRAITS:
        p_stats = _rank_composite(stat_ranks, config.stat_metrics.get(trait, {}))

        attrs = config.madden_attrs.get(trait, {})
        attr_values = {a: {} for a in attrs}
        for i, q in enumerate(season_rows):
            row = _madden_row(index, q.player_id, season,
                              lambda r, attrs=attrs: any(a in r for a in attrs))
            if row is None:
                continue
            for a in attrs:
                if a in row.ratings:
                    attr_values[a][i] = row.ratings[a]
        p_madden = _rank_composite(
            {a: percentiles(v) for a, v in attr_values.items()}, attrs)

        weights = config.weights[trait]
        out[trait] = {
            i: _blend(p_madden.get(i), p_stats.get(i), weights)
            for i in range(len(season_rows))
        }
    return out


# ------------------------------------------------------------- supporting cast


def _top_mean(values, n):
    top = sorted(values, reverse=True)[:n]
    return sum(top) / len(top) if top else None


def _cast_ranks(rosters, index, season, config):
    """For one season: {franchise: blended 0..1 Supporting Cast rank}."""
    by_team = defaultdict(list)
    for p in rosters:
        by_team[p.franchise_code].append(p)

    def has_attr(r):
        return config.cast_attr in r

    # slot -> side -> {franchise: mean of the team's top-n at that slot}
    slot_values = {s: {"madden": {}, "stats": {}} for s in config.cast_slots}
    for team, players in by_team.items():
        for slot, (_unit, top_n, _w) in config.cast_slots.items():
            at_slot = [p for p in players if p.slot_category == slot]
            av = _top_mean([p.av for p in at_slot if p.av is not None], top_n)
            if av is not None:
                slot_values[slot]["stats"][team] = av
            overalls = []
            for p in at_slot:
                row = _madden_row(index, p.player_id, season, has_attr)
                if row is not None:
                    overalls.append(row.ratings[config.cast_attr])
            rated = _top_mean(overalls, top_n)
            if rated is not None:
                slot_values[slot]["madden"][team] = rated

    halves = {}
    for unit in sorted({u for u, _, _ in config.cast_slots.values()}):
        slots = {s: w for s, (u, _n, w) in config.cast_slots.items() if u == unit}
        for side in ("madden", "stats"):
            ranks = {s: percentiles(slot_values[s][side]) for s in slots}
            halves[(unit, side)] = _rank_composite(ranks, slots)

    out = {}
    for team in by_team:
        unit_p = {}
        for unit in ("offense", "defense"):
            unit_p[unit] = _blend(halves.get((unit, "madden"), {}).get(team),
                                  halves.get((unit, "stats"), {}).get(team),
                                  config.weights[CAST])
        share = config.cast_offense_share
        if unit_p["offense"] is None and unit_p["defense"] is None:
            continue
        if unit_p["defense"] is None:
            out[team] = unit_p["offense"]
        elif unit_p["offense"] is None:
            out[team] = unit_p["defense"]
        else:
            out[team] = share * unit_p["offense"] + (1 - share) * unit_p["defense"]
    return out


def rosters_from_madden(madden, season, franchise_codes, slot_of):
    """A season's rosters read off the pre-season Madden edition's own team field.

    For a season the AV roster source does not cover at all. Who was on a team
    when the season opened is close to who played for it, but this carries no AV,
    so that season's Supporting Cast is the Madden side alone, and a player whose
    slot `slot_of` cannot place (or whose team is not a franchise) is left out.
    """
    out = []
    for m in madden:
        if m.edition != season:
            continue
        slot = slot_of.get(m.position)
        franchise = franchise_codes.get(m.team)
        if slot is None or franchise is None:
            continue
        out.append(RosterPlayer(franchise, season, m.player_id, slot, None))
    out.sort(key=lambda p: (p.franchise_code, p.player_id, p.slot_category))
    return out


# ----------------------------------------------------------------- overrides --


def apply_overrides(ratings, overrides):
    """Overwrite hand-corrected values. An override that matches no row raises:
    it is a typo in a file a person edits, and skipping it would look like a
    correction that had been made."""
    qb = {(r.franchise_code, r.season, r.player_id): r._asdict() for r in ratings.qb_rows}
    team = {(r.franchise_code, r.season): r._asdict() for r in ratings.team_rows}
    for o in overrides:
        if not 0 <= o.value <= 99:
            raise ValueError(f"override value {o.value} is outside 0-99: {o}")
        if o.slot == CAST:
            target, key, field = team, (o.franchise_code, o.season), CAST
        elif o.slot in TRAITS:
            target, key, field = qb, (o.franchise_code, o.season, o.player_id), o.slot
        else:
            raise ValueError(f"override for unknown slot {o.slot!r}: {o}")
        if key not in target:
            raise ValueError(f"override matches no row: {o}")
        target[key][field] = o.value
    return Ratings(
        [QbRatingRow(**qb[k]) for k in sorted(qb, key=lambda k: (k[1], k[0], k[2]))],
        [TeamRatingRow(**team[k]) for k in sorted(team, key=lambda k: (k[1], k[0]))],
    )


# -------------------------------------------------------------------- the seam


def transform(qb_seasons, madden, rosters, config, overrides=()):
    """Finished rating values for every qualifying quarterback-season and every
    team-season.

    `qb_seasons` are the qualifying rows (see `qb_seasons_from_weeks`),
    `madden` every `MaddenRating` the pipeline holds, `rosters` every
    `RosterPlayer`, and `config` the tuning. Rows come back sorted by season,
    franchise and player, so two runs over the same input — in any order — are
    byte-identical once written.
    """
    index = _index_madden(madden)

    by_season = defaultdict(list)
    for q in sorted(qb_seasons, key=lambda q: (q.season, q.franchise_code, q.player_id)):
        by_season[q.season].append(q)
    qb_rows = []
    for season in sorted(by_season):
        rows = by_season[season]
        ranks = _qb_season_ranks(rows, index, season, config)
        for i, q in enumerate(rows):
            qb_rows.append(QbRatingRow(
                q.franchise_code, q.season, q.player_id, q.display_name,
                *(_to_value(ranks[t][i], config) for t in TRAITS),
            ))

    roster_by_season = defaultdict(list)
    for p in rosters:
        roster_by_season[p.season].append(p)
    team_rows = []
    for season in sorted(roster_by_season):
        ranks = _cast_ranks(roster_by_season[season], index, season, config)
        for team in sorted(ranks):
            team_rows.append(TeamRatingRow(team, season, _to_value(ranks[team], config)))

    return apply_overrides(Ratings(qb_rows, team_rows), overrides)


# -------------------------------------------------------------------- checks --


def expectation_violations(ratings, expectations):
    """Known-quarterback sanity checks over finished values -> messages.

    An empty list means every expectation held. A check whose player or team
    has no row is itself a violation, so a typo cannot pass silently.
    """
    problems = []
    for e in expectations:
        if e.player_id:
            rows = [r for r in ratings.qb_rows
                    if r.player_id == e.player_id and r.season == e.season
                    and (not e.franchise_code or r.franchise_code == e.franchise_code)]
            values = [getattr(r, e.slot) for r in rows]
        else:
            rows = [r for r in ratings.team_rows
                    if r.season == e.season and r.franchise_code == e.franchise_code]
            values = [r.supporting_cast for r in rows]
        label = f"{e.player_id or e.franchise_code} {e.season} {e.slot}"
        if not values:
            problems.append(f"{label}: no such row ({e.note})")
            continue
        for v in values:
            if not e.low <= v <= e.high:
                problems.append(f"{label} = {v}, expected {e.low}-{e.high} ({e.note})")
    return problems
