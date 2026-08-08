"""nflverse weekly stats -> auction lot pool.

This module is the one seam in the pool build: parsed source rows and band
configuration in, finished `private.player_weeks` records out. Everything that
can be quietly wrong lives here — the filters, the period-correct team codes,
season aggregation, positional ranking, and band application. Fetching, artifact
writing and database loading stay outside it.

It is a pure function. No network, no filesystem, no clock, no globals that a
caller cannot pass in — which is what makes rebuilds byte-identical, and matters
now that the rows live in version-controlled migrations.
"""

from collections import Counter, defaultdict
from decimal import Decimal, ROUND_HALF_UP
from fractions import Fraction
from typing import NamedTuple

# The four positions that can fill a roster slot. Kickers, defenders and
# offensive linemen are in the source and are not lots.
POSITIONS = ("QB", "RB", "WR", "TE")

TIERS = ("star", "solid", "deep")

# nflverse normalises team codes to the modern franchise, so a 2015 game against
# San Diego comes back as `LAC`. The matchup is one of only four recall cues on
# a card, so the codes are reversed to what they were called at the time.
# (modern codes, period-correct code, last season under the old name)
RELOCATIONS = (
    (("LA", "LAR"), "STL", 2015),
    (("LAC",), "SD", 2016),
    (("LV",), "OAK", 2019),
)

# Washington needs no entry: the code stayed `WAS` across all three of its names.

ONE_DECIMAL = Decimal("0.1")


class PlayerWeek(NamedTuple):
    """One row of `private.player_weeks`, in column order.

    The first seven fields are the card-visible ones — name, position, season,
    week, matchup — and are safe to copy onto a client-readable lot row.
    `points` is the hidden half and must not travel with them. `pos_rank` and
    `tier` are player-*season* properties denormalised onto every week, so that
    dealing a board never has to recompute season aggregates at match start.
    """

    player_id: str
    display_name: str
    position: str
    season: int
    week: int
    team: str
    opponent: str
    points: Decimal
    pos_rank: int
    tier: str


class _Week(NamedTuple):
    """A source row that survived the filters, before its season is known."""

    week: int
    team: str
    opponent: str
    points: Decimal


def transform(source_rows, bands, *, rank_by="total"):
    """Turn nflverse source rows into finished player-weeks.

    `source_rows` are mappings in nflverse's own column names. `bands` maps a
    position to `{tier: (lowest_rank, highest_rank)}`; a player-season ranked
    outside every band for its position is dropped rather than emitted untiered.
    `rank_by` is "total" or "per_game" — see the note in `_rank_metric`.

    Returned rows are sorted by season, week, then player id, which is what
    makes two runs over the same input byte-identical.
    """
    if rank_by not in ("total", "per_game"):
        raise ValueError(f"unknown rank_by {rank_by!r}: expected 'total' or 'per_game'")

    seasons = _collect_seasons(source_rows)
    ranked = _rank_within_position(seasons, rank_by)

    out = []
    for (player_id, season), weeks in seasons.items():
        position, name = _season_position(weeks), _season_name(weeks)
        rank = ranked[(player_id, season)]
        tier = _tier_for(bands.get(position, {}), rank)
        if tier is None:
            continue
        for week in weeks["weeks"]:
            out.append(
                PlayerWeek(
                    player_id=player_id,
                    display_name=name,
                    position=position,
                    season=season,
                    week=week.week,
                    team=week.team,
                    opponent=week.opponent,
                    points=week.points,
                    pos_rank=rank,
                    tier=tier,
                )
            )

    out.sort(key=lambda r: (r.season, r.week, r.player_id))
    return out


# ------------------------------------------------------------------ filtering


def _collect_seasons(source_rows):
    """Group surviving rows by player-season, keeping what ranking will need.

    Grouping on player id alone — not player-and-team — is what makes a
    midseason trade aggregate into a single season total.
    """
    seasons = defaultdict(
        lambda: {"weeks": [], "positions": Counter(), "names": Counter(),
                 "total": Decimal("0.0")}
    )
    for row in source_rows:
        if row["season_type"] != "REG":
            continue
        position = row["position"]
        if position not in POSITIONS:
            continue

        season = int(row["season"])
        points = _round_points(row["fantasy_points_ppr"])
        entry = seasons[(row["player_id"], season)]
        entry["weeks"].append(
            _Week(
                week=int(row["week"]),
                team=_period_code(row["team"], season),
                opponent=_period_code(row["opponent_team"], season),
                points=points,
            )
        )
        entry["positions"][position] += 1
        entry["names"][row["player_display_name"]] += 1
        entry["total"] += points
    return seasons


def _round_points(raw):
    """The source carries float noise (27.62000000000001); the column is
    numeric(5,1). Rounding here rather than letting Postgres do it on insert
    keeps the artifact, the guards and the sampler agreed on one number."""
    return Decimal(raw).quantize(ONE_DECIMAL, rounding=ROUND_HALF_UP)


def _period_code(code, season):
    for modern, historical, last_season in RELOCATIONS:
        if code in modern and season <= last_season:
            return historical
    return code


def _modal(counter):
    """The most frequent entry, ties broken alphabetically.

    Not `Counter.most_common`, which leaves ties to insertion order — the exact
    kind of hidden input-ordering dependency that would make rebuilds differ.
    """
    return min(counter.items(), key=lambda kv: (-kv[1], kv[0]))[0]


def _season_position(entry):
    """One position per player-season, so that position, pos_rank and tier on a
    card always agree. A player listed at two positions in a season — the
    Taysom Hill case — takes the one he played most, ties broken alphabetically.
    """
    return _modal(entry["positions"])


def _season_name(entry):
    return _modal(entry["names"])


# ------------------------------------------------------------------- ranking


def _rank_within_position(seasons, rank_by):
    """Rank each player-season against its own position and season.

    Ties break by player id ascending. Any deterministic rule would do; the
    point is that rebuilding the artifact twice must produce identical output,
    which an unspecified tie-break does not guarantee.
    """
    fields = defaultdict(list)
    for (player_id, season), entry in seasons.items():
        fields[(season, _season_position(entry))].append((player_id, entry))

    ranks = {}
    for (season, _position), members in fields.items():
        members.sort(key=lambda m: (-_rank_metric(m[1], rank_by), m[0]))
        for i, (player_id, _entry) in enumerate(members, start=1):
            ranks[(player_id, season)] = i
    return ranks


def _rank_metric(entry, rank_by):
    """Season total, or points per game.

    Total is the default and means a star who missed six games ranks like a
    mediocre full-season one — 2023 Joe Burrow lands in the deep tier. That is
    left in on purpose: tier is never shown to players and only shapes the mix.
    Per-game is here so the mix can be tuned by trying the alternative.

    Exact rationals, not floats, so the comparison cannot drift between runs.
    """
    total = Fraction(entry["total"])
    if rank_by == "per_game":
        return total / len(entry["weeks"])
    return total


def _tier_for(position_bands, rank):
    """The tier whose band contains this rank, or None if no band does.

    None means the player-season is dropped entirely — every one of its weeks.
    Bands need not be contiguous, so a gap between them drops the ranks inside.
    """
    for tier in TIERS:
        band = position_bands.get(tier)
        if band and band[0] <= rank <= band[1]:
            return tier
    return None
