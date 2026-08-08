#!/usr/bin/env python3
"""Build the auction's lot pool from nflverse weekly player statistics.

    # write the data migration for the full era
    python3 scripts/player_pool/build_pool.py --out supabase/migrations/xxxx_pool.sql

    # deal a sample board and read the names, to tune the tier bands
    python3 scripts/player_pool/build_pool.py --sample

    # a single new season, as a new migration (history is append-only)
    python3 scripts/player_pool/build_pool.py --from 2026 --to 2026 --out ...

This is a run-once ETL, not a pipeline. The seasons it reads are frozen history
and will never change, so there is no scheduler, no cache invalidation and no
freshness logic. Extending the era range when a season finishes is a re-run with
one number changed.

Python 3, standard library only, on purpose: the application never imports this,
and stdlib `csv` does the whole job where a TypeScript version would pull in a
parser dependency and a test runner for a script with nothing to do with the app.
"""

import argparse
import csv
import io
import random
import ssl
import sys
import urllib.request
from decimal import Decimal
from pathlib import Path

from transform import POSITIONS, RELOCATIONS, TIERS, transform

# ------------------------------------------------------------------- tuning --

# Tier bands, per position, as inclusive positional-finish ranges.
#
# These are the tuning dial for pool composition, and they are placeholders
# rather than settled values. Tune them by running --sample across several
# seasons and reading the names it produces, not by argument: tier is never
# shown to players, so getting a band slightly wrong is a matter of feel.
#
# Bands are per position because positions are not equally deep — in 2023 there
# were 81 QBs with a season total and 224 WRs, so rank 25-40 is a backup at one
# and a fantasy starter at the other. One uniform range would leave the WR pool
# with no deep cuts in it at all, which is exactly the collapse the deep tier
# exists to prevent.
#
# They are passed into the transform rather than read from inside it, which is
# what keeps tuning one edit away from the transform logic and lets the tests
# drive it with their own bands.
DEFAULT_BANDS = {
    #        star      solid       deep
    "QB": {"star": (1, 5), "solid": (6, 18), "deep": (19, 32)},
    "RB": {"star": (1, 5), "solid": (6, 24), "deep": (25, 45)},
    "WR": {"star": (1, 5), "solid": (6, 30), "deep": (31, 60)},
    "TE": {"star": (1, 5), "solid": (6, 18), "deep": (19, 32)},
}

FIRST_SEASON, LAST_SEASON = 2010, 2025

SOURCE_URL = (
    "https://github.com/nflverse/nflverse-data/releases/download/"
    "stats_player/stats_player_week_{season}.csv"
)

CACHE_DIR = Path(__file__).parent / ".cache"

# Guard bounds on rows per season, as weeks per tiered player-season. The bands
# fix exactly how many player-seasons a season can contribute, so deriving the
# bound from them keeps the guard honest when the bands are tuned rather than
# turning it into a number to bump whenever it complains. 18 is the hard ceiling
# — no player has more regular-season weeks than that. 10 is the floor: seasons
# run 14-15 weeks per tiered player in practice, and a truncated download or a
# season that is still in progress lands well below it.
WEEKS_PER_SEASON_BOUND = (10, 18)

# Rows per insert statement. Large enough that statement overhead is noise,
# small enough that the artifact stays readable in a diff viewer.
BATCH_SIZE = 1_000

TABLE = "private.player_weeks"
COLUMNS = (
    "player_id", "display_name", "position", "season", "week",
    "team", "opponent", "points", "pos_rank", "tier",
)

# --------------------------------------------------------------------- fetch --


# Where macOS keeps its trust store. Only consulted when the running Python has
# no CA bundle of its own — a python.org install whose Install Certificates
# command was never run. Verification stays on either way: these rows end up
# committed as migration content, so an unverified download is not an option.
SYSTEM_CA_BUNDLE = "/etc/ssl/cert.pem"


def ssl_context():
    context = ssl.create_default_context()
    if context.cert_store_stats()["x509_ca"]:
        return context
    if Path(SYSTEM_CA_BUNDLE).exists():
        context.load_verify_locations(cafile=SYSTEM_CA_BUNDLE)
        return context
    raise SystemExit(
        "No CA certificates available to verify the download.\n"
        "On a python.org install, run:\n"
        "  /Applications/Python\\ 3.x/Install\\ Certificates.command"
    )


def fetch_season(season, refresh=False):
    """One season of source CSV, cached on disk so re-runs do not re-download."""
    CACHE_DIR.mkdir(exist_ok=True)
    cached = CACHE_DIR / f"stats_player_week_{season}.csv"
    if refresh or not cached.exists():
        url = SOURCE_URL.format(season=season)
        print(f"  fetching {season} ...", end=" ", flush=True, file=sys.stderr)
        with urllib.request.urlopen(url, context=ssl_context()) as response:
            cached.write_bytes(response.read())
        print(f"{cached.stat().st_size // 1024} KB", file=sys.stderr)
    return cached


def read_seasons(seasons, refresh=False):
    rows = []
    for season in seasons:
        with fetch_season(season, refresh).open(newline="", encoding="utf-8") as f:
            rows.extend(csv.DictReader(f))
    return rows


# -------------------------------------------------------------------- guards --

class GuardFailure(Exception):
    """The build's own output looks wrong. Never write a bad artifact."""


def band_slots(bands):
    """How many player-seasons the bands admit per season, per position.

    Counted as ranks covered rather than highest rank, so a gap between bands
    is accounted for rather than overstated.
    """
    return sum(hi - lo + 1
               for position_bands in bands.values()
               for lo, hi in position_bands.values())


def check(condition, message):
    if not condition:
        raise GuardFailure(message)


def run_guards(rows, source_rows, bands, seasons, rank_by):
    """Fail the build rather than warn.

    These catch a different class of problem than the unit tests do: corruption
    and coverage rather than logic. They run over the real output, which the
    unit tests never see.
    """
    check(rows, "transform produced no rows at all")

    # Coverage: dealing a board draws from every position-and-tier cell, so an
    # empty one is a board that cannot be dealt to quota.
    populated = {(r.position, r.tier) for r in rows}
    missing = [(p, t) for p in POSITIONS for t in TIERS if (p, t) not in populated]
    check(not missing, f"empty position/tier cells: {missing}")

    keys = {(r.player_id, r.season, r.week) for r in rows}
    check(len(keys) == len(rows),
          f"duplicate primary key: {len(rows)} rows, {len(keys)} distinct")

    # Period-correct team codes. A modern code surviving before its cutoff means
    # the remapping silently missed a column or a franchise.
    for modern, historical, last_season in RELOCATIONS:
        stale = [r for r in rows
                 if r.season <= last_season and (r.team in modern or r.opponent in modern)]
        check(not stale,
              f"{len(stale)} rows still carry {modern} before {last_season + 1} "
              f"(expected {historical}), e.g. {stale[0] if stale else ''}")
    # And the reverse: the historical code must not leak forward.
    for _modern, historical, last_season in RELOCATIONS:
        early = [r for r in rows
                 if r.season > last_season and (r.team == historical or r.opponent == historical)]
        check(not early, f"{len(early)} rows carry {historical} after {last_season}")

    for row in rows:
        check(row.season in seasons, f"season {row.season} outside {seasons}")
        # Mirrors the table's own `check (season >= 2010)`. The range check above
        # only sees the seasons this run asked for, so it cannot catch a row the
        # database would reject.
        check(row.season >= FIRST_SEASON,
              f"season {row.season} is before {FIRST_SEASON}, which the table rejects")
        check(1 <= row.week <= 18, f"implausible week {row.week} in {row}")
        check(row.position in POSITIONS, f"bad position {row.position}")
        check(row.tier in TIERS, f"bad tier {row.tier}")
        check(row.pos_rank > 0, f"bad rank {row.pos_rank}")
        check(row.display_name.strip(), f"blank display name for {row.player_id}")
        check(row.team and row.opponent, f"blank matchup in {row}")
        # Points must be present and must fit numeric(5,1). Negatives are
        # expected, not rejected — a fumble-heavy week really does score below
        # zero, and duds are what make a bid a bid.
        check(row.points is not None, f"null points in {row}")
        check(abs(row.points) < Decimal("10000"), f"points overflow numeric(5,1): {row}")
        check(-row.points.as_tuple().exponent <= 1, f"points not at 1dp: {row}")

    slots = band_slots(bands)
    low, high = (slots * w for w in WEEKS_PER_SEASON_BOUND)
    for season in seasons:
        count = sum(1 for r in rows if r.season == season)
        check(low <= count <= high,
              f"season {season} produced {count} rows, expected {low}-{high} "
              f"({slots} tiered player-seasons x "
              f"{WEEKS_PER_SEASON_BOUND[0]}-{WEEKS_PER_SEASON_BOUND[1]} weeks)")

        # Each band slot is one player-season by construction; more means the
        # ranking leaked across a season or position boundary.
        player_seasons = len({r.player_id for r in rows if r.season == season})
        check(player_seasons <= slots,
              f"season {season} has {player_seasons} player-seasons, "
              f"more than the {slots} the bands admit")

    # Determinism, checked on the bytes that actually get committed rather than
    # on the records, so that the emitter's own ordering and formatting are
    # covered too. The rows live in version-controlled migrations now, and a
    # non-deterministic build would show up forever as spurious diffs.
    #
    # The second run is over *shuffled* input. Comparing two runs over identically
    # ordered rows proves almost nothing — it is precisely the dict, set and
    # Counter iteration order inherited from input order that could leak into a
    # rank or a tie-break, and only reordering the input can surface that.
    shuffled = list(source_rows)
    random.Random(0).shuffle(shuffled)
    check(emit_sql(transform(shuffled, bands, rank_by=rank_by), seasons)
          == emit_sql(rows, seasons),
          "build is not deterministic: reordering the source changed the artifact")


# ---------------------------------------------------------------------- emit --


def sql_literal(value):
    if isinstance(value, (int, Decimal)):
        return str(value)
    return "'" + str(value).replace("'", "''") + "'"


def emit_sql(rows, seasons):
    """The data migration: the finished rows as batched multi-row INSERTs.

    WHY NOT `copy ... from stdin`, which is the obvious compact choice: the
    Supabase CLI applies migrations over the extended query protocol, and inline
    copy data desynchronises that connection — `db push` dies with SQLSTATE
    08P01 partway through the file. Verified, not assumed.
    """
    out = io.StringIO()
    span = f"{min(seasons)}-{max(seasons)}" if len(seasons) > 1 else str(seasons[0])
    out.write(
        f"-- The auction's lot pool, {span}: {len(rows):,} player-weeks.\n"
        "--\n"
        "-- Generated by scripts/player_pool/build_pool.py. Do not hand-edit, and do\n"
        "-- not regenerate this file once it has been applied: migration history is\n"
        "-- append-only, so a future season arrives as a new migration inserting that\n"
        "-- season's rows, leaving already-deployed environments consistent.\n"
        "--\n"
        "-- Source: nflverse-data, tag stats_player, one CSV per season.\n\n"
    )
    header = f"insert into {TABLE} ({', '.join(COLUMNS)}) values\n"
    for start in range(0, len(rows), BATCH_SIZE):
        batch = rows[start:start + BATCH_SIZE]
        out.write(header)
        out.write(",\n".join(
            "  (" + ", ".join(sql_literal(v) for v in row) + ")" for row in batch
        ))
        out.write(";\n\n")
    return out.getvalue()


# ------------------------------------------------------------------- sampler --


# One board, as the game deals it: 4 players x [QB, RB, WR, TE] base plus one
# flex each, against a 7/8/5 tier quota. See docs/games/auction_team_builder.md.
BASE_POSITIONS = {"QB": 4, "RB": 4, "WR": 4, "TE": 4}
FLEX_POSITIONS = ("RB", "WR", "TE")
FLEX_LOTS = 4
TIER_QUOTA = {"star": 7, "solid": 8, "deep": 5}


def deal_sample_board(rows, rng):
    """Deal one board straight from the transform's output and hand it back.

    A diagnostic preview of pool composition, not the real dealer — actual lot
    scheduling, the base-then-flex ordering and the bidding quotas belong to the
    auction. This exists so band values can be tuned by reading names, without
    pushing anything to a database.
    """
    positions = [p for p, n in BASE_POSITIONS.items() for _ in range(n)]
    positions += [rng.choice(FLEX_POSITIONS) for _ in range(FLEX_LOTS)]
    tiers = [t for t, n in TIER_QUOTA.items() for _ in range(n)]
    assert len(positions) == len(tiers), "position and tier quotas must agree"

    # Pair the position quota against the tier quota at random. Every cell is
    # non-empty (a guard), so any pairing can be filled.
    rng.shuffle(positions)
    rng.shuffle(tiers)

    by_cell = {}
    for row in rows:
        by_cell.setdefault((row.position, row.tier), []).append(row)

    board, used = [], set()
    for position, tier in zip(positions, tiers):
        candidates = [r for r in by_cell[(position, tier)]
                      if (r.player_id, r.season) not in used]
        pick = rng.choice(candidates or by_cell[(position, tier)])
        used.add((pick.player_id, pick.season))
        board.append(pick)
    return board


def print_board(board):
    print(f"\n{'':4} {'PLAYER':22} {'POS':4} {'WHEN':16} {'VS':6} {'FPTS':>6}  TIER")
    print("-" * 72)
    for i, lot in enumerate(board, start=1):
        when = f"{lot.season} Wk {lot.week}"
        print(f"{i:>3}. {lot.display_name[:22]:22} {lot.position:4} {when:16} "
              f"{lot.opponent:6} {lot.points:>6}  {lot.tier}")
    total = sum(lot.points for lot in board)
    print("-" * 72)
    print(f"{'':4} {len(board)} lots · {total} total FPTS · "
          f"mean {total / len(board):.1f} · "
          f"{sum(1 for l in board if l.points <= 0)} at or below zero\n")


def print_pool_summary(rows, seasons):
    print(f"\n{len(rows):,} player-weeks across {len(seasons)} seasons\n")
    print(f"{'':6} {'star':>10} {'solid':>10} {'deep':>10} {'total':>10}")
    for position in POSITIONS:
        counts = [sum(1 for r in rows if r.position == position and r.tier == t)
                  for t in TIERS]
        print(f"{position:6} " + "".join(f"{c:>10,}" for c in counts)
              + f"{sum(counts):>10,}")
    print()


# ----------------------------------------------------------------------- cli --


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    parser.add_argument("--from", dest="first", type=int, default=FIRST_SEASON,
                        help=f"first season (default {FIRST_SEASON})")
    parser.add_argument("--to", dest="last", type=int, default=LAST_SEASON,
                        help=f"last season (default {LAST_SEASON})")
    parser.add_argument("--out", type=Path,
                        help="write the data migration here")
    parser.add_argument("--sample", action="store_true",
                        help="deal a sample board and print it; writes nothing")
    parser.add_argument("--boards", type=int, default=1,
                        help="how many sample boards to deal (default 1)")
    parser.add_argument("--seed", type=int,
                        help="seed the sampler, to compare band values fairly")
    parser.add_argument("--rank-by", choices=["total", "per_game"], default="total",
                        help="rank player-seasons on season total or per game")
    parser.add_argument("--refresh", action="store_true",
                        help="re-download the source instead of using the cache")
    args = parser.parse_args(argv)

    if not args.out and not args.sample:
        parser.error("nothing to do: pass --out to write a migration, or --sample")
    if args.first > args.last:
        parser.error(f"--from {args.first} is after --to {args.last}")

    seasons = list(range(args.first, args.last + 1))
    print(f"seasons {args.first}-{args.last}, ranking by {args.rank_by}",
          file=sys.stderr)
    source_rows = read_seasons(seasons, args.refresh)
    print(f"  {len(source_rows):,} source rows", file=sys.stderr)

    rows = transform(source_rows, DEFAULT_BANDS, rank_by=args.rank_by)
    print(f"  {len(rows):,} player-weeks after filtering and tiering",
          file=sys.stderr)

    try:
        run_guards(rows, source_rows, DEFAULT_BANDS, seasons, args.rank_by)
    except GuardFailure as failure:
        print(f"\nGUARD FAILED: {failure}", file=sys.stderr)
        return 1
    print("  guards passed", file=sys.stderr)

    if args.sample:
        print_pool_summary(rows, seasons)
        rng = random.Random(args.seed)
        for _ in range(args.boards):
            print_board(deal_sample_board(rows, rng))

    if args.out:
        args.out.write_text(emit_sql(rows, seasons), encoding="utf-8")
        size = args.out.stat().st_size
        print(f"  wrote {args.out} ({size / 1_048_576:.1f} MB)", file=sys.stderr)

    return 0


if __name__ == "__main__":
    sys.exit(main())
