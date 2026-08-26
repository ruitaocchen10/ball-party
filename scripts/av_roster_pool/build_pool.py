#!/usr/bin/env python3
"""Build sabotage draft's roster pool: nflverse (2006-2019) + a cached Pro
Football Reference scrape (2020-present).

    # write the data migration for the full era
    python3 scripts/av_roster_pool/build_pool.py --out supabase/migrations/xxxx_pool.sql

    # a quick look at pool composition; writes nothing
    python3 scripts/av_roster_pool/build_pool.py --sample

This is a run-once ETL, not a pipeline, in the same spirit as
`scripts/player_pool/build_pool.py`: the seasons it reads are frozen history
and will never change, so there is no scheduler and no freshness logic.

Unlike that script, the PFR half of the fetch cannot run here. PFR sits
behind a Cloudflare JS challenge that no stdlib HTTP client can pass — see
`../pfr_scrape.js` for the browser-console procedure that produces the cache
file this script reads (`--pfr-cache`, default `.cache/pfr_<first>_<last>.txt`).
The nflverse half is a plain CSV download and fetches itself, same as the
existing pool.

Python 3, standard library only for everything this script itself does. The
application never imports any of this.
"""

import argparse
import csv
import io
import random
import ssl
import sys
import urllib.request
from pathlib import Path

from transform import FRANCHISE_CODE, SLOT_CATEGORIES, coverage, transform

FIRST_SEASON, LAST_SEASON = 2006, 2025
NFLVERSE_LAST_SEASON = 2019  # nfldata/rosters.csv's own last season.

NFLVERSE_URL = (
    "https://raw.githubusercontent.com/nflverse/nfldata/master/data/rosters.csv"
)

CACHE_DIR = Path(__file__).parent / ".cache"
NFLVERSE_CACHE = CACHE_DIR / "rosters.csv"

TABLE = "private.av_roster_players"
COLUMNS = ("franchise_code", "season", "player_id", "display_name", "slot_category", "av")

BATCH_SIZE = 1_000

# ---------------------------------------------------------------------- fetch --

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


def fetch_nflverse(refresh=False):
    """nfldata/rosters.csv, cached on disk so re-runs do not re-download."""
    CACHE_DIR.mkdir(exist_ok=True)
    if refresh or not NFLVERSE_CACHE.exists():
        print("  fetching nflverse rosters.csv ...", end=" ", flush=True, file=sys.stderr)
        with urllib.request.urlopen(NFLVERSE_URL, context=ssl_context()) as response:
            NFLVERSE_CACHE.write_bytes(response.read())
        print(f"{NFLVERSE_CACHE.stat().st_size // 1024} KB", file=sys.stderr)
    with NFLVERSE_CACHE.open(newline="", encoding="utf-8") as f:
        return list(csv.DictReader(f))


def read_pfr_cache(path):
    """The pre-scraped PFR lines. See ../pfr_scrape.js for how this is made.

    There is no automatic fetch step for this half on purpose: nothing in the
    Python standard library can get past Cloudflare's JS challenge, so this
    file is a checked-in-adjacent artifact of a manual, one-time browser
    scrape, not something this script can regenerate itself.
    """
    if not path.exists():
        raise SystemExit(
            f"missing PFR cache: {path}\n"
            "This is produced by a one-time browser scrape, not by this "
            "script — see ../pfr_scrape.js for the procedure. Run it, save "
            "the result at this path, and re-run the build."
        )
    return path.read_text(encoding="utf-8").splitlines()


# -------------------------------------------------------------------- guards --

class GuardFailure(Exception):
    """The build's own output looks wrong. Never write a bad artifact."""


def check(condition, message):
    if not condition:
        raise GuardFailure(message)


def run_guards(rows, nflverse_rows, pfr_lines, seasons):
    check(rows, "transform produced no rows at all")

    # Coverage: dealing a round draws from every franchise/slot cell, so an
    # empty one is a slot the game cannot deal for that franchise at all.
    populated = coverage(rows)
    missing = [(code, slot) for code in FRANCHISE_CODE.values() for slot in SLOT_CATEGORIES
               if (code, slot) not in populated]
    check(not missing, f"empty franchise/slot cells: {missing}")

    keys = {(r.franchise_code, r.season, r.player_id, r.slot_category) for r in rows}
    check(len(keys) == len(rows),
          f"duplicate primary key: {len(rows)} rows, {len(keys)} distinct")

    known_codes = set(FRANCHISE_CODE.values())
    for row in rows:
        check(row.season in seasons, f"season {row.season} outside {seasons}")
        check(row.season >= FIRST_SEASON,
              f"season {row.season} is before {FIRST_SEASON}, which the table rejects")
        check(row.franchise_code in known_codes, f"unknown franchise code {row.franchise_code}")
        check(row.slot_category in SLOT_CATEGORIES, f"bad slot category {row.slot_category}")
        check(row.display_name.strip(), f"blank display name for {row.player_id}")
        # Negative AV is real, not a data error: AV's own methodology can
        # score a genuinely bad season below zero (confirmed in the source —
        # e.g. a handful of QBs and kickers with a single-digit negative AV
        # season). The sanity bound here is generous on purpose; it exists to
        # catch a parsing error, not to second-guess PFR's own metric.
        check(-20 <= row.av <= 100, f"implausible av in {row}")

    # Determinism, checked on the emitted bytes so the emitter's own ordering
    # is covered too, the same reasoning as scripts/player_pool/build_pool.py.
    # The second run is over shuffled input, not just re-run over the same
    # order: only reordering the input can surface an accidental dependence
    # on input order leaking into iteration or a tie-break.
    shuffled_nflverse = list(nflverse_rows)
    shuffled_pfr = list(pfr_lines)
    random.Random(0).shuffle(shuffled_nflverse)
    random.Random(1).shuffle(shuffled_pfr)
    check(emit_sql(transform(shuffled_nflverse, shuffled_pfr))
          == emit_sql(rows),
          "build is not deterministic: reordering the source changed the artifact")


# ---------------------------------------------------------------------- emit --


def sql_literal(value):
    if isinstance(value, int):
        return str(value)
    return "'" + str(value).replace("'", "''") + "'"


def emit_sql(rows):
    out = io.StringIO()
    span = f"{FIRST_SEASON}-{LAST_SEASON}"
    out.write(
        f"-- Sabotage draft's roster pool, {span}: {len(rows):,} player-seasons\n"
        "-- across ten slot categories (QB/RB/WR/TE plus OL/DL/LB/CB/S/ST).\n"
        "--\n"
        "-- Generated by scripts/av_roster_pool/build_pool.py. Do not hand-edit, and\n"
        "-- do not regenerate this file once it has been applied: migration history\n"
        "-- is append-only, so extending the era range arrives as a new migration.\n"
        "--\n"
        f"-- Sources: nflverse nfldata/rosters.csv ({FIRST_SEASON}-{NFLVERSE_LAST_SEASON})\n"
        f"-- and a cached Pro Football Reference scrape ({NFLVERSE_LAST_SEASON + 1}-"
        f"{LAST_SEASON}, see ../../scripts/av_roster_pool/pfr_scrape.js).\n\n"
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


def print_summary(rows):
    print(f"\n{len(rows):,} player-seasons across {FIRST_SEASON}-{LAST_SEASON}\n")
    by_slot = {}
    for row in rows:
        by_slot.setdefault(row.slot_category, []).append(row)
    print(f"{'':6} {'rows':>10} {'franchises':>12} {'mean av':>10}")
    for slot in SLOT_CATEGORIES:
        slot_rows = by_slot.get(slot, [])
        franchises = len({r.franchise_code for r in slot_rows})
        mean_av = sum(r.av for r in slot_rows) / len(slot_rows) if slot_rows else 0.0
        print(f"{slot:6} {len(slot_rows):>10,} {franchises:>12} {mean_av:>10.1f}")
    print()


# ----------------------------------------------------------------------- cli --


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    parser.add_argument("--out", type=Path, help="write the data migration here")
    parser.add_argument("--sample", action="store_true",
                        help="print pool composition; writes nothing")
    parser.add_argument("--pfr-cache", type=Path,
                        default=CACHE_DIR / f"pfr_{NFLVERSE_LAST_SEASON + 1}_{LAST_SEASON}.txt",
                        help="path to the cached PFR scrape (see ../pfr_scrape.js)")
    parser.add_argument("--refresh", action="store_true",
                        help="re-download nflverse's CSV instead of using the cache")
    args = parser.parse_args(argv)

    if not args.out and not args.sample:
        parser.error("nothing to do: pass --out to write a migration, or --sample")

    seasons = list(range(FIRST_SEASON, LAST_SEASON + 1))

    nflverse_rows = fetch_nflverse(args.refresh)
    print(f"  {len(nflverse_rows):,} nflverse source rows", file=sys.stderr)

    pfr_lines = read_pfr_cache(args.pfr_cache)
    print(f"  {len(pfr_lines):,} cached PFR source lines", file=sys.stderr)

    rows = transform(nflverse_rows, pfr_lines)
    print(f"  {len(rows):,} roster rows after folding and filtering", file=sys.stderr)

    try:
        run_guards(rows, nflverse_rows, pfr_lines, seasons)
    except GuardFailure as failure:
        print(f"\nGUARD FAILED: {failure}", file=sys.stderr)
        return 1
    print("  guards passed", file=sys.stderr)

    if args.sample:
        print_summary(rows)

    if args.out:
        args.out.write_text(emit_sql(rows), encoding="utf-8")
        size = args.out.stat().st_size
        print(f"  wrote {args.out} ({size / 1_048_576:.1f} MB)", file=sys.stderr)

    return 0


if __name__ == "__main__":
    sys.exit(main())
