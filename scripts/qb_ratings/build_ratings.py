#!/usr/bin/env python3
"""Build QB Season Builder's finished ratings from nflverse weekly stats, the
private Madden ratings snapshot and the AV roster pool.

    # write the data migration
    python3 scripts/qb_ratings/build_ratings.py --out supabase/migrations/xxxx_ratings.sql

    # look at the distributions and the known quarterbacks; writes nothing
    python3 scripts/qb_ratings/build_ratings.py --sample

    # the no-go path: Madden weight 0 for every slot, no Madden rows loaded
    python3 scripts/qb_ratings/build_ratings.py --stat-only --out ...

A run-once ETL in the spirit of `scripts/av_roster_pool/build_pool.py`: the
seasons it reads are frozen history, so there is no scheduler and no freshness
logic. Everything that can be quietly wrong is in `transform.py`; this file is
fetching, the guards that fail the build on a clearly wrong result, and the
artifact.

Inputs, all cached under `.cache/` (gitignored) or the AV pool's own cache:

- nflverse weekly player stats, 2006-2025 (fetched on first run)
- nflverse players.csv, for the GSIS -> Pro Football Reference id crosswalk and
  heights and weights (fetched on first run)
- the Madden ratings snapshot: `--madden-dir`, a folder of one CSV per edition
  (`2006.csv` ... `2025.csv`, the dataset's `data/madden/processed/`). NEVER
  fetched or mirrored by this script — see
  docs/games/qb_season_builder/madden_data.md, condition 4.
- the AV roster pool's caches (`../av_roster_pool/.cache/`), for who was on
  which roster and what each was worth in Approximate Value.

Python 3, standard library only. The application never imports any of this.
"""

import argparse
import csv
import importlib.util
import io
import random
import ssl
import sys
import urllib.request
from collections import Counter, defaultdict
from pathlib import Path

from config import DEFAULT_CONFIG, EXPECTATIONS, MADDEN_SLOT_OF, STAT_ONLY
from transform import (
    CAST, TRAITS, MaddenRating, Override, RosterPlayer, Ratings,
    expectation_violations, qb_seasons_from_weeks, rosters_from_madden, transform, _madden_row,
)

FIRST_SEASON, LAST_SEASON = 2006, 2025

HERE = Path(__file__).parent
CACHE_DIR = HERE / ".cache"
AV_CACHE_DIR = HERE.parent / "av_roster_pool" / ".cache"
OVERRIDES_CSV = HERE / "overrides.csv"

WEEK_URL = ("https://github.com/nflverse/nflverse-data/releases/download/"
            "stats_player/stats_player_week_{season}.csv")
PLAYERS_URL = "https://github.com/nflverse/nflverse-data/releases/download/players/players.csv"
ROSTERS_URL = "https://raw.githubusercontent.com/nflverse/nfldata/master/data/rosters.csv"
NFLVERSE_ROSTER_LAST_SEASON = 2019

# The private table's rating columns: (key the transform uses, the snapshot's
# CSV column, the table's column). One list, so the reader and the emitter
# cannot disagree about a name.
MADDEN_COLUMNS = (
    ("overall", "overallrating", "overall"),
    ("throwpower", "throwpower", "throw_power"),
    ("throwaccuracyshort", "throwaccuracyshort", "throw_accuracy_short"),
    ("throwaccuracymid", "throwaccuracymid", "throw_accuracy_mid"),
    ("throwaccuracydeep", "throwaccuracydeep", "throw_accuracy_deep"),
    ("speed", "speed", "speed"),
    ("acceleration", "acceleration", "acceleration"),
    ("agility", "agility", "agility"),
    ("awareness", "awareness", "awareness"),
    ("strength", "strength", "strength"),
    ("toughness", "toughness", "toughness"),
    ("injury", "injury", "injury"),
    ("stamina", "stamina", "stamina"),
    ("playaction", "playaction", "play_action"),
    ("throwonrun", "throwonrun", "throw_on_run"),
)

QB_TABLE = "qb_season_builder_private.qb_seasons"
TEAM_TABLE = "qb_season_builder_private.team_seasons"
MADDEN_TABLE = "qb_season_builder_private.madden_ratings"
OVERRIDE_TABLE = "qb_season_builder_private.rating_overrides"
BATCH_SIZE = 1_000

# nflverse's weekly files use the modern team codes (LA, LV), which the AV
# pool's map — built for a roster file that uses period-correct ones — lacks.
EXTRA_TEAM_CODES = {"LA": "ram", "LAR": "ram", "LV": "rai"}

# ------------------------------------------------------------------- guards --

# Per-season bounds on how many rows a healthy build yields. Real seasons run
# 36-43 qualifying quarterbacks and always 32 team-seasons; the bounds exist to
# catch a truncated download or a broken join, not to second-guess the league.
QB_ROWS_PER_SEASON = (28, 55)
TEAMS_PER_SEASON = (30, 34)
# The share of qualifying quarterback-seasons that must carry Madden inputs. The
# license ticket measured 96.4% with an observed overall; a collapse means the
# id join broke and the 70% Madden weights are silently doing nothing.
MADDEN_QB_COVERAGE_FLOOR = 0.90
# The same for the players the Supporting Cast reads: the share of counted
# roster spots (each team-season's top-N at every configured slot) with a rating.
MADDEN_CAST_COVERAGE_FLOOR = 0.85
# A trait must actually separate quarterbacks within a season.
MIN_SPREAD = 8.0


class GuardFailure(Exception):
    """The build's own output looks wrong. Never write a bad artifact."""


def check(condition, message):
    if not condition:
        raise GuardFailure(message)


# -------------------------------------------------------------------- fetch --

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


def cached(url, path, refresh=False):
    """Download once; re-runs read the cache."""
    path.parent.mkdir(parents=True, exist_ok=True)
    if refresh or not path.exists():
        print(f"  fetching {path.name} ...", end=" ", flush=True, file=sys.stderr)
        with urllib.request.urlopen(url, context=ssl_context()) as response:
            path.write_bytes(response.read())
        print(f"{path.stat().st_size // 1024} KB", file=sys.stderr)
    return path


def read_csv(path):
    with path.open(newline="", encoding="utf-8") as f:
        return list(csv.DictReader(f))


def load_av_transform():
    """The AV pool's own transform, imported by path so its position folding and
    franchise identity stay the one definition. Loaded under another name because
    this package has a `transform` module of its own."""
    path = HERE.parent / "av_roster_pool" / "transform.py"
    spec = importlib.util.spec_from_file_location("av_roster_transform", path)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


# ------------------------------------------------------------------ adapters --


def float_or_none(text):
    text = (text or "").strip()
    return float(text) if text not in ("", "NA") else None


def read_people(rows):
    """players.csv -> {gsis_id: (pfr_id, display_name, height, weight)}."""
    return {
        r["gsis_id"]: (r["pfr_id"], r["display_name"],
                       float_or_none(r["height"]), float_or_none(r["weight"]))
        for r in rows if r.get("gsis_id") and r.get("pfr_id")
    }


def read_madden(directory, people):
    """The snapshot's editions -> MaddenRating rows.

    Only observed ratings: a blank `overallrating` is a player the edition lists
    without rating, and is left out rather than filled in. A player's PFR id is
    the snapshot's own, else the crosswalk's through his GSIS id. Two rows for
    one (edition, player) keep the higher overall.
    """
    best = {}
    for edition in range(FIRST_SEASON, LAST_SEASON + 1):
        path = directory / f"{edition}.csv"
        if not path.exists():
            raise SystemExit(
                f"missing Madden edition file: {path}\n"
                "Point --madden-dir at a folder of one CSV per edition (the "
                "dataset's data/madden/processed/). This script never fetches "
                "it: see docs/games/qb_season_builder/madden_data.md."
            )
        for r in read_csv(path):
            overall = float_or_none(r.get("overallrating"))
            if overall is None:
                continue
            pfr_id = r.get("pfr_id") or (people.get(r["player_id"]) or ("",))[0]
            if not pfr_id:
                continue
            ratings = {}
            for key, column, _db in MADDEN_COLUMNS:
                v = float_or_none(r.get(column))
                if v is not None:
                    ratings[key] = v
            row = MaddenRating(edition, pfr_id, r["position"], ratings, r.get("team", ""))
            key = (edition, pfr_id)
            if key not in best or ratings["overall"] > best[key].ratings["overall"]:
                best[key] = row
    return list(best.values())


def read_rosters(refresh=False):
    """The AV pool's roster rows for the era, as RosterPlayer."""
    av = load_av_transform()
    rosters = cached(ROSTERS_URL, AV_CACHE_DIR / "rosters.csv", refresh)
    # Every PFR scrape cache the AV pool holds, so a scrape that fills a gap
    # (nflverse's roster file stops at the start of 2019) is picked up by being
    # saved next to the others as pfr_<first>_<last>.txt.
    pfr_caches = sorted(AV_CACHE_DIR.glob("pfr_*.txt"))
    if not pfr_caches:
        raise SystemExit(
            f"missing PFR cache under {AV_CACHE_DIR}\n"
            "It is produced by a one-time browser scrape; see "
            "scripts/av_roster_pool/pfr_scrape.js and its README."
        )
    lines = [line for path in pfr_caches for line in path.read_text(encoding="utf-8").splitlines()]
    rows = av.transform(read_csv(rosters), lines)
    return [RosterPlayer(r.franchise_code, r.season, r.player_id, r.slot_category, float(r.av))
            for r in rows if FIRST_SEASON <= r.season <= LAST_SEASON], av.FRANCHISE_CODE


def read_overrides(path):
    if not path.exists():
        return []
    return [Override(r["franchise_code"], int(r["season"]), r["player_id"], r["slot"],
                     int(r["value"]), r.get("reason", ""))
            for r in read_csv(path)]


def madden_rows_needed(qb_rows, rosters, madden, config):
    """The Madden rows the transform can read: for each rated quarterback-season
    and each counted roster spot, the edition after the season and the
    pre-season one. Nothing else is loaded into the private table."""
    wanted = set()
    for r in qb_rows:
        wanted |= {(r.season, r.player_id), (r.season + 1, r.player_id)}
    for p in rosters:
        if p.slot_category in config.cast_slots:
            wanted |= {(p.season, p.player_id), (p.season + 1, p.player_id)}
    return sorted((m for m in madden if (m.edition, m.player_id) in wanted),
                  key=lambda m: (m.edition, m.player_id))


# -------------------------------------------------------------------- guards --


def madden_qb_coverage(qb_seasons, madden, config):
    index = {(m.edition, m.player_id): m for m in madden}
    have = 0
    for q in qb_seasons:
        row = _madden_row(index, q.player_id, q.season, lambda r: config.cast_attr in r)
        have += row is not None
    return have / len(qb_seasons) if qb_seasons else 0.0


def madden_cast_coverage(rosters, madden, config):
    index = {(m.edition, m.player_id): m for m in madden}
    by_cell = defaultdict(list)
    for p in rosters:
        if p.slot_category in config.cast_slots:
            by_cell[(p.franchise_code, p.season, p.slot_category)].append(p)
    counted = rated = 0
    for (_team, season, slot), players in by_cell.items():
        top_n = config.cast_slots[slot][1]
        for p in sorted(players, key=lambda p: (-(p.av or 0), p.player_id))[:top_n]:
            counted += 1
            rated += _madden_row(index, p.player_id, season,
                                 lambda r: config.cast_attr in r) is not None
    return rated / counted if counted else 0.0


def run_guards(ratings, qb_seasons, rosters, madden, config, expectations, args):
    qb_rows, team_rows = ratings
    check(qb_rows and team_rows, "transform produced no rows at all")

    per_season = Counter(r.season for r in qb_rows)
    teams_per_season = Counter(r.season for r in team_rows)
    for season in range(FIRST_SEASON, LAST_SEASON + 1):
        low, high = QB_ROWS_PER_SEASON
        check(low <= per_season[season] <= high,
              f"{season}: {per_season[season]} qualifying quarterbacks, expected {low}-{high}")
        low, high = TEAMS_PER_SEASON
        check(teams_per_season[season] > 0,
              f"{season}: no roster source. The AV roster pool has no {season} rows and, "
              "with Madden off, nothing else names who was on each team. Scrape that "
              "season's rosters from Pro Football Reference (scripts/av_roster_pool/"
              f"pfr_scrape.js) and save it beside the others as pfr_{season}_{season}.txt")
        check(low <= teams_per_season[season] <= high,
              f"{season}: {teams_per_season[season]} team-seasons, expected {low}-{high}")

    teams = {(r.franchise_code, r.season) for r in team_rows}
    check(len(teams) == len(team_rows), "duplicate team-season primary key")
    keys = {(r.franchise_code, r.season, r.player_id) for r in qb_rows}
    check(len(keys) == len(qb_rows), "duplicate quarterback-season primary key")
    for r in qb_rows:
        # The schema's foreign key, checked here so the failure names the row.
        check((r.franchise_code, r.season) in teams,
              f"{r.display_name} {r.season}: {r.franchise_code} has no Supporting Cast row")
        check(r.display_name.strip(), f"blank display name for {r.player_id}")
        for trait in TRAITS:
            check(0 <= getattr(r, trait) <= 99, f"{trait} outside 0-99 in {r}")
    for r in team_rows:
        check(0 <= r.supporting_cast <= 99, f"supporting cast outside 0-99 in {r}")

    # A trait that stopped separating quarterbacks is a dead input: the ranking
    # would still produce values, all of them noise.
    for season in range(FIRST_SEASON, LAST_SEASON + 1):
        rows = [r for r in qb_rows if r.season == season]
        for trait in TRAITS:
            values = [getattr(r, trait) for r in rows]
            mean = sum(values) / len(values)
            spread = (sum((v - mean) ** 2 for v in values) / len(values)) ** 0.5
            check(spread >= MIN_SPREAD, f"{season} {trait}: spread {spread:.1f} < {MIN_SPREAD}")

    if not args.stat_only:
        cover = madden_qb_coverage(qb_seasons, madden, config)
        check(cover >= MADDEN_QB_COVERAGE_FLOOR,
              f"only {cover:.1%} of quarterback-seasons have a Madden rating "
              f"(floor {MADDEN_QB_COVERAGE_FLOOR:.0%}) — the id join has probably broken")
        cover = madden_cast_coverage(rosters, madden, config)
        check(cover >= MADDEN_CAST_COVERAGE_FLOOR,
              f"only {cover:.1%} of counted roster spots have a Madden rating "
              f"(floor {MADDEN_CAST_COVERAGE_FLOOR:.0%}) — the id join has probably broken")

    problems = expectation_violations(ratings, expectations)
    check(not problems, "known-quarterback checks failed:\n  " + "\n  ".join(problems))

    # Determinism, over shuffled input, on the emitted bytes so the emitter's own
    # ordering is covered too.
    shuffled = [list(x) for x in (qb_seasons, madden, rosters)]
    for i, x in enumerate(shuffled):
        random.Random(i).shuffle(x)
    again = transform(*shuffled, config, args.overrides)
    check(emit_sql(again, args.madden_rows, args.overrides) == emit_sql(ratings, args.madden_rows, args.overrides),
          "build is not deterministic: reordering the source changed the artifact")


# ---------------------------------------------------------------------- emit --


def sql_literal(value):
    if value is None:
        return "null"
    if isinstance(value, int):
        return str(value)
    if isinstance(value, float):
        return str(int(value)) if value == int(value) else repr(value)
    return "'" + str(value).replace("'", "''") + "'"


def _insert(out, table, columns, rows):
    header = f"insert into {table} ({', '.join(columns)}) values\n"
    for start in range(0, len(rows), BATCH_SIZE):
        batch = rows[start:start + BATCH_SIZE]
        out.write(header)
        out.write(",\n".join(
            "  (" + ", ".join(sql_literal(v) for v in row) + ")" for row in batch))
        out.write(";\n\n")


def emit_sql(ratings, madden_rows, overrides):
    qb_rows, team_rows = ratings
    out = io.StringIO()
    out.write(
        f"-- QB Season Builder's finished ratings, {FIRST_SEASON}-{LAST_SEASON}: "
        f"{len(qb_rows):,} quarterback-seasons\n"
        f"-- and {len(team_rows):,} team-seasons, the private Madden rows they were built "
        f"from ({len(madden_rows):,}),\n"
        "-- and the hand overrides already applied to them.\n"
        "--\n"
        "-- Generated by scripts/qb_ratings/build_ratings.py. Do not hand-edit, and do\n"
        "-- not regenerate this file once it has been applied: migration history is\n"
        "-- append-only, so a retune arrives as a new migration.\n"
        "--\n"
        "-- THIS FILE CARRIES THIRD-PARTY RATINGS (qb_season_builder_private.madden_ratings).\n"
        "-- It must never reach a public repository: see\n"
        "-- docs/games/qb_season_builder/madden_data.md, condition 2.\n"
        "--\n"
        "-- The tables it fills are created by 0120 and 0123. Every generated file\n"
        "-- replaces all four outright, so a retune is just a newer file: the deletes\n"
        "-- also clear placeholder rows an older local database may still hold from a\n"
        "-- previous seed.sql, and on a fresh or hosted database they clear nothing.\n\n"
    )
    out.write("delete from qb_season_builder_private.qb_seasons;\n"
              "delete from qb_season_builder_private.team_seasons;\n"
              "delete from qb_season_builder_private.madden_ratings;\n"
              "delete from qb_season_builder_private.rating_overrides;\n\n")
    _insert(out, TEAM_TABLE, ("franchise_code", "season", "supporting_cast"), team_rows)
    _insert(out, QB_TABLE,
            ("franchise_code", "season", "player_id", "display_name") + TRAITS, qb_rows)
    if madden_rows:
        columns = ("edition", "player_id", "position") + tuple(db for _k, _c, db in MADDEN_COLUMNS)
        rows = [(m.edition, m.player_id, m.position)
                + tuple(None if k not in m.ratings else int(m.ratings[k])
                        for k, _c, _db in MADDEN_COLUMNS)
                for m in madden_rows]
        _insert(out, MADDEN_TABLE, columns, rows)
    if overrides:
        _insert(out, OVERRIDE_TABLE,
                ("franchise_code", "season", "player_id", "slot", "value", "reason"),
                [tuple(o) for o in overrides])
        # Already applied by the build; this is the invariant, and it fails the
        # migration if an override in the file matched no row.
        out.write("select qb_season_builder_private.apply_rating_overrides();\n")
    return out.getvalue()


# ------------------------------------------------------------------- sampler --


def print_summary(ratings, qb_seasons, madden, rosters, config, args):
    qb_rows, team_rows = ratings
    print(f"\n{len(qb_rows):,} quarterback-seasons, {len(team_rows):,} team-seasons\n")
    if not args.stat_only:
        print(f"Madden coverage: quarterbacks {madden_qb_coverage(qb_seasons, madden, config):.1%}, "
              f"counted cast spots {madden_cast_coverage(rosters, madden, config):.1%}\n")
    print(f"{'':16} {'mean':>6} {'sd':>6} {'min':>5} {'max':>5}")
    for trait in TRAITS:
        values = [getattr(r, trait) for r in qb_rows]
        mean = sum(values) / len(values)
        sd = (sum((v - mean) ** 2 for v in values) / len(values)) ** 0.5
        print(f"{trait:16} {mean:6.1f} {sd:6.1f} {min(values):5d} {max(values):5d}")
    values = [r.supporting_cast for r in team_rows]
    mean = sum(values) / len(values)
    sd = (sum((v - mean) ** 2 for v in values) / len(values)) ** 0.5
    print(f"{CAST:16} {mean:6.1f} {sd:6.1f} {min(values):5d} {max(values):5d}")

    for season in (2007, 2018, 2023):
        print(f"\n{season}, by average of the five qualities:")
        rows = sorted((r for r in qb_rows if r.season == season),
                      key=lambda r: -sum(getattr(r, t) for t in TRAITS))
        print(f"  {'':22} {'team':5}" + "".join(f"{t[:5]:>7}" for t in TRAITS))
        for r in rows[:6] + rows[-3:]:
            print(f"  {r.display_name:22} {r.franchise_code:5}"
                  + "".join(f"{getattr(r, t):7d}" for t in TRAITS))
        casts = sorted((r for r in team_rows if r.season == season),
                       key=lambda r: -r.supporting_cast)
        print("  cast, top / bottom: "
              + ", ".join(f"{r.franchise_code} {r.supporting_cast}" for r in casts[:5])
              + "  /  " + ", ".join(f"{r.franchise_code} {r.supporting_cast}" for r in casts[-5:]))
    print()


# ----------------------------------------------------------------------- cli --


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    parser.add_argument("--out", type=Path, help="write the data migration here")
    parser.add_argument("--sample", action="store_true",
                        help="print distributions and known quarterbacks; writes nothing")
    parser.add_argument("--stat-only", dest="stat_only", action="store_true",
                        help="the no-go path: Madden weight 0 everywhere, no Madden rows")
    parser.add_argument("--madden-dir", dest="madden_dir", type=Path,
                        default=CACHE_DIR / "madden",
                        help="folder of one CSV per Madden edition (never fetched here)")
    parser.add_argument("--overrides", type=Path, default=OVERRIDES_CSV,
                        help="the hand overrides file")
    parser.add_argument("--refresh", action="store_true",
                        help="re-download nflverse's files instead of using the cache")
    args = parser.parse_args(argv)
    if not args.out and not args.sample:
        parser.error("nothing to do: pass --out to write a migration, or --sample")

    config = DEFAULT_CONFIG
    if args.stat_only:
        config = config._replace(weights=STAT_ONLY)

    print("  reading sources ...", file=sys.stderr)
    players = read_people(read_csv(cached(PLAYERS_URL, CACHE_DIR / "players.csv", args.refresh)))
    rosters, av_franchise_codes = read_rosters(args.refresh)
    franchise_codes = {**av_franchise_codes, **EXTRA_TEAM_CODES}

    week_rows = []
    for season in range(FIRST_SEASON, LAST_SEASON + 1):
        path = cached(WEEK_URL.format(season=season),
                      CACHE_DIR / f"stats_player_week_{season}.csv", args.refresh)
        week_rows.extend(read_csv(path))
    print(f"  {len(week_rows):,} weekly stat rows, {len(rosters):,} roster rows", file=sys.stderr)

    qb_seasons = qb_seasons_from_weeks(week_rows, players, franchise_codes, config.min_attempts)
    print(f"  {len(qb_seasons):,} qualifying quarterback-seasons", file=sys.stderr)

    madden = [] if args.stat_only else read_madden(args.madden_dir, players)
    print(f"  {len(madden):,} Madden rows", file=sys.stderr)

    # A season the AV roster source does not cover at all has its rosters read
    # off the pre-season Madden edition and no AV. (Only when Madden is in use:
    # on the no-go path that season needs its PFR scrape instead, and the
    # per-season guard below says so.)
    covered = {p.season for p in rosters}
    for season in range(FIRST_SEASON, LAST_SEASON + 1):
        if season not in covered and madden:
            filled = rosters_from_madden(madden, season, franchise_codes, MADDEN_SLOT_OF)
            print(f"  {season}: no AV roster rows, {len(filled):,} rostered players "
                  "read from the pre-season Madden edition", file=sys.stderr)
            rosters = rosters + filled

    args.overrides = read_overrides(args.overrides)
    ratings = transform(qb_seasons, madden, rosters, config, args.overrides)
    args.madden_rows = madden_rows_needed(ratings.qb_rows, rosters, madden, config)

    try:
        run_guards(ratings, qb_seasons, rosters, madden, config, EXPECTATIONS, args)
    except GuardFailure as failure:
        print(f"\nGUARD FAILED: {failure}", file=sys.stderr)
        if args.sample:
            print_summary(ratings, qb_seasons, madden, rosters, config, args)
        return 1
    print("  guards passed", file=sys.stderr)

    if args.sample:
        print_summary(ratings, qb_seasons, madden, rosters, config, args)

    if args.out:
        args.out.write_text(emit_sql(ratings, args.madden_rows, args.overrides), encoding="utf-8")
        print(f"  wrote {args.out} ({args.out.stat().st_size / 1_048_576:.1f} MB)", file=sys.stderr)
    return 0


if __name__ == "__main__":
    sys.exit(main())
