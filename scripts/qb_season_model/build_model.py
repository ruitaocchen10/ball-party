#!/usr/bin/env python3
"""Fit QB Season Builder's season model on the real 2006-2025 seasons.

    # write the data migration
    python3 scripts/qb_season_model/build_model.py --out supabase/migrations/xxxx_season_model_data.sql

    # look at the fit, the awards and the known quarterbacks; writes nothing
    python3 scripts/qb_season_model/build_model.py --sample

A run-once ETL in the spirit of `scripts/qb_ratings/build_ratings.py`: the seasons
it reads are frozen history, so there is no scheduler and no freshness logic.
Everything that can be quietly wrong is in `transform.py`; this file is fetching,
the guards that fail the build on a clearly wrong fit, and the artifact.

Inputs:

- the finished ratings, read from the ratings data migration (`--ratings`, by
  default the newest one under supabase/migrations). Reading the artifact and not
  re-running the ratings pipeline means the fit is of exactly what a player is
  dealt, and needs no Madden snapshot.
- nflverse weekly player stats, 2006-2025, for each quarterback's real line
  (cached under `.cache/`, or the ratings pipeline's own cache, else fetched)
- nflverse players.csv, for the GSIS -> Pro Football Reference id crosswalk
- nflverse games.csv, for every team's record and how far it went in the playoffs
- `awards.csv`: the real quarterback award winners, checked in

Python 3, standard library only. The application never imports any of this.
"""

import argparse
import csv
import importlib.util
import io
import math
import random
import re
import ssl
import sys
import urllib.request
from collections import Counter
from pathlib import Path

from config import (
    AVERAGE_BUILD, AWARD_SHARE_BOUNDS, DEFAULT_CONFIG, EXPECTATIONS, MIN_R_SQUARED,
    TOP_BUILD_MAX_BEATEN, TOP_BUILD_MIN_PERCENTILE,
)
from transform import (
    AWARDS, SLOTS, Award, RatedSeason, composite, earns, expected_depth,
    expected_metrics, fit, nearest_real_seasons, percentile_of,
    qb_lines_from_weeks, real_seasons, score, season_metrics, sigmoid,
    team_seasons_from_games, values_of,
)

FIRST_SEASON, LAST_SEASON = 2006, 2025

HERE = Path(__file__).parent
REPO = HERE.parent.parent
CACHE_DIR = HERE / ".cache"
RATINGS_CACHE_DIR = HERE.parent / "qb_ratings" / ".cache"
AV_DIR = HERE.parent / "av_roster_pool"
AWARDS_CSV = HERE / "awards.csv"
MIGRATIONS_DIR = REPO / "supabase" / "migrations"

WEEK_URL = ("https://github.com/nflverse/nflverse-data/releases/download/"
            "stats_player/stats_player_week_{season}.csv")
PLAYERS_URL = "https://github.com/nflverse/nflverse-data/releases/download/players/players.csv"
GAMES_URL = "https://raw.githubusercontent.com/nflverse/nfldata/master/data/games.csv"

# nflverse's files use the modern team codes (LA, LV), which the AV pool's map,
# built for a roster file with period-correct ones, lacks.
EXTRA_TEAM_CODES = {"LA": "ram", "LV": "rai"}

PRIVATE = "qb_season_builder_private"
BATCH_SIZE = 1_000

# ------------------------------------------------------------------- limits --

# Per-season bounds on how many rows a healthy build sees: they exist to catch a
# truncated download or a broken join, not to second-guess the league.
QB_ROWS_PER_SEASON = (28, 55)
TEAMS_PER_SEASON = (30, 34)
# The AP names exactly one first-team quarterback a year; a Pro Bowl has several.
PRO_BOWL_PER_SEASON = (4, 14)


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


def cached(url, name, refresh=False):
    """The file from this build's cache or the ratings pipeline's, else fetched once."""
    for directory in (CACHE_DIR, RATINGS_CACHE_DIR):
        if not refresh and (directory / name).exists():
            return directory / name
    path = CACHE_DIR / name
    path.parent.mkdir(parents=True, exist_ok=True)
    print(f"  fetching {name} ...", end=" ", flush=True, file=sys.stderr)
    with urllib.request.urlopen(url, context=ssl_context()) as response:
        path.write_bytes(response.read())
    print(f"{path.stat().st_size // 1024} KB", file=sys.stderr)
    return path


def read_csv(path):
    with path.open(newline="", encoding="utf-8") as f:
        return list(csv.DictReader(f))


def load_av_franchise_codes():
    """The AV pool's franchise identity, imported by path so it stays the one
    definition. Loaded under another name because this package has a `transform`
    module of its own."""
    spec = importlib.util.spec_from_file_location("av_roster_transform", AV_DIR / "transform.py")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module.FRANCHISE_CODE


# ------------------------------------------------------------------ adapters --

_FIELD = re.compile(r"'((?:[^']|'')*)'|(-?\d+(?:\.\d+)?)|(null)")


def parse_insert_rows(sql, table):
    """The rows of `insert into <table> (...) values (...), (...);` as tuples.

    Reads only the shape the ratings generator writes: one row per line, strings
    single-quoted with '' for a quote, numbers and null bare. Every insert into
    the table in the file is read, in order.
    """
    rows = []
    for block in re.finditer(
            rf"insert into {re.escape(table)} \([^)]*\) values\n(.*?);\n", sql, re.S):
        for line in block.group(1).splitlines():
            line = line.strip()
            if not line.startswith("("):
                continue
            fields = []
            for quoted, number, null in _FIELD.findall(line):
                if null:
                    fields.append(None)
                elif number:
                    fields.append(float(number) if "." in number else int(number))
                else:
                    fields.append(quoted.replace("''", "'"))
            rows.append(tuple(fields))
    return rows


def newest_ratings_migration():
    """The newest migration that loads finished ratings. Every generated ratings
    file replaces the tables outright, so the newest one is the whole truth."""
    candidates = [p for p in sorted(MIGRATIONS_DIR.glob("*qb_season_builder_ratings*.sql"))
                  if f"insert into {PRIVATE}.qb_seasons" in p.read_text(encoding="utf-8")]
    if not candidates:
        raise SystemExit(f"no ratings data migration under {MIGRATIONS_DIR}; run the ratings "
                         "pipeline (scripts/qb_ratings) first")
    return candidates[-1]


def read_ratings(path):
    """The ratings migration -> RatedSeason rows, each with its team's Supporting Cast."""
    sql = path.read_text(encoding="utf-8")
    cast = {(franchise, season): value
            for franchise, season, value in parse_insert_rows(sql, f"{PRIVATE}.team_seasons")}
    rows = []
    for franchise, season, player, name, acc, arm, mob, iq, bld in parse_insert_rows(
            sql, f"{PRIVATE}.qb_seasons"):
        if (franchise, season) not in cast:
            raise SystemExit(f"{name} {season}: {franchise} has no Supporting Cast row in {path.name}")
        rows.append(RatedSeason(franchise, season, player, name, acc, arm, mob, iq, bld,
                                cast[(franchise, season)]))
    return rows


def read_awards(path):
    return [Award(int(r["season"]), r["award"], r["player_id"]) for r in read_csv(path)]


def read_pfr_ids(rows):
    """players.csv -> {gsis_id: pfr_id}."""
    return {r["gsis_id"]: r["pfr_id"] for r in rows if r.get("gsis_id") and r.get("pfr_id")}


# -------------------------------------------------------------------- guards --


def award_shares(model, seasons, config):
    """The share of all real seasons whose metrics clear each award's threshold."""
    metrics = [season_metrics(s, config) for s in seasons]
    return {a: sum(earns(model, a, m) for m in metrics) / len(metrics) for a in AWARDS}


def run_guards(model, rated, teams, awards, seasons, config):
    per_season = Counter(s.season for s in seasons)
    teams_per_season = Counter(t.season for t in teams)
    for season in range(FIRST_SEASON, LAST_SEASON + 1):
        low, high = QB_ROWS_PER_SEASON
        check(low <= per_season[season] <= high,
              f"{season}: {per_season[season]} real quarterback-seasons, expected {low}-{high}")
        low, high = TEAMS_PER_SEASON
        check(low <= teams_per_season[season] <= high,
              f"{season}: {teams_per_season[season]} team results, expected {low}-{high}")
    check(len(seasons) == len(rated), "the join dropped or added a rated season")

    counts = Counter((a.season, a.award) for a in awards)
    for season in range(FIRST_SEASON, LAST_SEASON + 1):
        check(counts[(season, "all_pro")] == 1,
              f"{season}: {counts[(season, 'all_pro')]} first-team All-Pro quarterbacks, expected 1")
        low, high = PRO_BOWL_PER_SEASON
        check(low <= counts[(season, "pro_bowl")] <= high,
              f"{season}: {counts[(season, 'pro_bowl')]} Pro Bowl quarterbacks, expected {low}-{high}")
        check(counts[(season, "mvp")] <= 1 and counts[(season, "opoy")] <= 1,
              f"{season}: more than one MVP or Offensive Player of the Year")

    # Each formula has to explain something, or its coefficients are noise.
    for o in model.outputs:
        check(o.r_squared >= MIN_R_SQUARED[o.name],
              f"{o.name}: the six values explain {o.r_squared:.1%} of it "
              f"(floor {MIN_R_SQUARED[o.name]:.0%}); the formula is not tracking the data")
        check(all(math.isfinite(v) and abs(v) < 1e6 for v in (o.intercept, *o.coefficients, o.residual_sd)),
              f"{o.name}: a coefficient is not a finite number")
        rs = [r for _, r in o.residuals]
        check(rs == sorted(rs) and rs[0] < 0 < rs[-1], f"{o.name}: the residual table is not a spread")

    # A fitted formula, not a lookup: a top-of-scale build beats every real season
    # and a bottom-of-scale one loses to nearly all of them.
    top = expected_metrics(model.outputs, (99,) * 6)
    top["playoff_depth"] = expected_depth(model.ladder, top["wins"])
    real_stat = [composite(model, "stat_line", season_metrics(s, config)) for s in seasons]
    top_stat = composite(model, "stat_line", top)
    beaten_by = sum(1 for x in real_stat if x > top_stat)
    check(beaten_by <= TOP_BUILD_MAX_BEATEN,
          f"a top-of-scale build's stat line ({top_stat:.2f}) is beaten by {beaten_by} real seasons "
          f"(at most {TOP_BUILD_MAX_BEATEN}; the best is {max(real_stat):.2f}); the fit is not allowed to extrapolate")
    check(percentile_of(model.distributions["stat_line"], top_stat) >= TOP_BUILD_MIN_PERCENTILE,
          "a top-of-scale stat line does not score at the top of the real distribution")
    bottom = expected_metrics(model.outputs, (25,) * 6)
    bottom_stat = composite(model, "stat_line", bottom)
    check(bottom_stat < sorted(real_stat)[len(real_stat) // 10],
          f"a bottom-of-scale build's stat line ({bottom_stat:.2f}) is not in the worst real decile")
    check(top["wins"] > bottom["wins"], "a better build does not win more")
    # The team side can beat any real season too: wins cannot pass 17, so the
    # expectation may not, but a top-of-scale build with the best of its luck (the
    # top of its real spread on wins) and the title is above every real season.
    lucky = expected_metrics(model.outputs, (99,) * 6, {"wins": 1.0})
    lucky["playoff_depth"] = 5.0
    best_team = max(composite(model, "team_success", season_metrics(s, config)) for s in seasons)
    check(composite(model, "team_success", lucky) > best_team,
          "a top-of-scale build with the best of its luck does not beat every real season on team success")

    # Awards: reachable at the top of the scale, not handed to an average build,
    # and not so cheap that any good real season would have taken them.
    avg = expected_metrics(model.outputs, AVERAGE_BUILD)
    for a in AWARDS:
        check(earns(model, a, top), f"a top-of-scale build does not earn {a}")
    for a in ("mvp", "opoy", "all_pro"):
        check(not earns(model, a, avg), f"an average build earns {a}")
    shares = award_shares(model, seasons, config)
    for a, share in shares.items():
        check(share <= AWARD_SHARE_BOUNDS[a],
              f"{a}: {share:.1%} of real seasons clear its threshold "
              f"(bound {AWARD_SHARE_BOUNDS[a]:.0%}); it would be handed out to any good season")

    problems = []
    for e in EXPECTATIONS:
        matches = [s for s in seasons if s.player_id == e.player_id and s.season == e.season
                   and (not e.franchise_code or s.franchise_code == e.franchise_code)]
        if not matches:
            problems.append(f"{e.player_id} {e.season}: not among the real seasons")
            continue
        s = max(matches, key=lambda x: x.attempts)
        m = expected_metrics(model.outputs, values_of(s))
        value = m[e.metric]
        if not e.low <= value <= e.high:
            problems.append(f"{s.display_name} {s.season} expected {e.metric} {value:,.1f}, "
                            f"outside {e.low:,}-{e.high:,}: {e.note}")
    check(not problems, "known-quarterback checks failed:\n  " + "\n  ".join(problems))

    # Determinism, on the emitted bytes so the emitter's own ordering is covered.
    shuffled = [list(seasons), list(teams)]
    for i, x in enumerate(shuffled):
        random.Random(i).shuffle(x)
    again = fit(shuffled[0], shuffled[1], config)
    check(emit_sql(again, awards) == emit_sql(model, awards),
          "build is not deterministic: reordering the source changed the artifact")


# ---------------------------------------------------------------------- emit --


def sql_literal(value):
    if value is None:
        return "null"
    if isinstance(value, bool):
        return "true" if value else "false"
    if isinstance(value, int):
        return str(value)
    if isinstance(value, float):
        return str(int(value)) if value == int(value) and abs(value) < 1e15 else repr(value)
    return "'" + str(value).replace("'", "''") + "'"


def _insert(out, table, columns, rows):
    header = f"insert into {PRIVATE}.{table} ({', '.join(columns)}) values\n"
    for start in range(0, len(rows), BATCH_SIZE):
        batch = rows[start:start + BATCH_SIZE]
        out.write(header)
        out.write(",\n".join(
            "  (" + ", ".join(sql_literal(v) for v in row) + ")" for row in batch))
        out.write(";\n\n")


TABLES = (  # children before parents, for the deletes
    "season_model_residuals", "season_model_coefficients", "season_model_outputs",
    "season_model_playoff_ladder", "season_model_metrics", "season_model_formulas",
    "season_model_awards", "season_model_distributions", "season_model_real_seasons",
)


def emit_sql(model, awards):
    out = io.StringIO()
    out.write(
        f"-- QB Season Builder's season model, fitted on the {len(model.real):,} real "
        f"quarterback-seasons of\n"
        f"-- {FIRST_SEASON}-{LAST_SEASON}: the formulas from the six values to a season, the real "
        "residual spread,\n"
        "-- the playoff ladder, the award thresholds, the score distributions and the real "
        "seasons\n"
        "-- themselves for the closest-real-season comparison.\n"
        "--\n"
        "-- Generated by scripts/qb_season_model/build_model.py from the finished ratings\n"
        "-- (0124) and nflverse's real results. Do not hand-edit, and do not regenerate this\n"
        "-- file once it has been applied: migration history is append-only, so a retune\n"
        "-- arrives as a new migration.\n"
        "--\n"
        "-- The tables are created by 0125. Every generated file replaces all of them\n"
        "-- outright, so the newest one is the whole truth.\n\n"
    )
    for table in TABLES:
        out.write(f"delete from {PRIVATE}.{table};\n")
    out.write("\n")

    _insert(out, "season_model_outputs",
            ("output", "link", "low", "high", "intercept", "residual_sd", "r_squared",
             "noise_scale", "noise_group"),
            [(o.name, o.spec.link, o.spec.low, o.spec.high, o.intercept, o.residual_sd,
              o.r_squared, o.spec.noise_scale, o.spec.group) for o in model.outputs])
    _insert(out, "season_model_coefficients", ("output", "slot", "coefficient"),
            [(o.name, slot, c) for o in model.outputs for slot, c in zip(SLOTS, o.coefficients)])
    _insert(out, "season_model_residuals", ("output", "p", "residual"),
            [(o.name, p, r) for o in model.outputs for p, r in o.residuals])
    _insert(out, "season_model_playoff_ladder", ("rung", "step", "intercept", "slope"),
            [(i + 1, r.step, r.intercept, r.slope) for i, r in enumerate(model.ladder)])
    _insert(out, "season_model_metrics", ("metric", "mean", "sd"),
            [(n.metric, n.mean, n.sd) for n in model.norms])
    _insert(out, "season_model_formulas", ("formula", "term", "weight"),
            [tuple(f) for f in model.formulas])
    _insert(out, "season_model_awards",
            ("award", "threshold", "spread", "noise_scale", "winners", "requires"),
            [tuple(a) for a in model.awards])
    _insert(out, "season_model_distributions", ("component", "p", "value"),
            [(c, p, v) for c, table in sorted(model.distributions.items()) for p, v in table])
    _insert(out, "season_model_real_seasons",
            ("franchise_code", "season", "player_id", "display_name") + SLOTS
            + ("attempts", "completions", "pass_yards", "pass_tds", "interceptions",
               "rush_yards", "rush_tds", "wins", "losses", "ties", "playoff_depth") + AWARDS,
            [(s.franchise_code, s.season, s.player_id, s.display_name)
             + tuple(getattr(s, slot) for slot in SLOTS)
             + (s.attempts, s.completions, round(s.pass_yards), s.pass_tds, s.interceptions,
                round(s.rush_yards), s.rush_tds, s.wins, s.losses, s.ties, s.playoff_depth)
             + tuple(a in s.awards for a in AWARDS)
             for s in model.real])
    return out.getvalue()


# ------------------------------------------------------------------- sampler --


def print_summary(model, seasons, config):
    print(f"\n{len(seasons):,} real quarterback-seasons\n")
    print(f"{'output':11} {'link':9} {'R2':>6} {'sd':>7} {'noise':>6}  "
          + " ".join(f"{s[:6]:>8}" for s in SLOTS))
    for o in model.outputs:
        print(f"{o.name:11} {o.spec.link:9} {o.r_squared:6.2f} {o.residual_sd:7.3f} "
              f"{o.spec.noise_scale:6.2f}  " + " ".join(f"{c:8.4f}" for c in o.coefficients))

    print("\nplayoff ladder, P(clear | reached), by wins:")
    print(f"  {'':18} " + " ".join(f"{w:>6}" for w in (4, 8, 10, 12, 14, 16)))
    for r in model.ladder:
        print(f"  {r.step:18} " + " ".join(
            f"{sigmoid(r.intercept + r.slope * w):6.2f}" for w in (4, 8, 10, 12, 14, 16)))

    shares = award_shares(model, seasons, config)
    print("\nawards:")
    for a in model.awards:
        print(f"  {a.award:9} winners {a.winners:3}  threshold {a.threshold:6.2f}  "
              f"spread {a.spread:5.2f}  cleared by {shares[a.award]:5.1%} of real seasons")

    print("\nexpected seasons (six values -> line, per 17 games):")
    header = f"  {'':26} {'yards':>6} {'TD':>4} {'INT':>4} {'rate':>6} {'rush':>5} {'wins':>5} {'depth':>6} {'score':>6}"
    print(header)
    builds = [("all 99", (99,) * 6), ("all 75", (75,) * 6), ("average", AVERAGE_BUILD),
              ("all 40", (40,) * 6), ("all 25", (25,) * 6)]
    for name, values in builds:
        m = expected_metrics(model.outputs, values)
        m["playoff_depth"] = expected_depth(model.ladder, m["wins"])
        print(f"  {name:26} {m['pass_yards']:6,.0f} {m['pass_td']:4.0f} {m['interceptions']:4.0f} "
              f"{m['rating']:6.1f} {m['rush_yards']:5.0f} {m['wins']:5.1f} {m['playoff_depth']:6.2f} "
              f"{score(model, m):6.1f}")
    print("\nknown quarterbacks, their own six values through the fit (real -> expected):")
    seen = set()
    for e in EXPECTATIONS:
        if (e.player_id, e.season) in seen:
            continue
        seen.add((e.player_id, e.season))
        matches = [x for x in seasons if x.player_id == e.player_id and x.season == e.season]
        if not matches:
            continue
        s = matches[0]
        m = expected_metrics(model.outputs, values_of(s))
        real = season_metrics(s, config)
        near = nearest_real_seasons(model, values_of(s), 2)[1]
        print(f"  {s.display_name:18} {s.season}  yards {real['pass_yards']:5,.0f} -> {m['pass_yards']:5,.0f}"
              f"   TD {real['pass_td']:3.0f} -> {m['pass_td']:3.0f}"
              f"   rush {real['rush_yards']:4.0f} -> {m['rush_yards']:4.0f}"
              f"   wins {real['wins']:4.1f} -> {m['wins']:4.1f}   (next closest: {near.display_name} {near.season})")
    print()


# ----------------------------------------------------------------------- cli --


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    parser.add_argument("--out", type=Path, help="write the data migration here")
    parser.add_argument("--sample", action="store_true",
                        help="print the fit and the known quarterbacks; writes nothing")
    parser.add_argument("--ratings", type=Path,
                        help="the ratings data migration to fit (default: the newest)")
    parser.add_argument("--awards", type=Path, default=AWARDS_CSV, help="the real award winners")
    parser.add_argument("--refresh", action="store_true",
                        help="re-download nflverse's files instead of using the cache")
    args = parser.parse_args(argv)
    if not args.out and not args.sample:
        parser.error("nothing to do: pass --out to write a migration, or --sample")

    config = DEFAULT_CONFIG
    ratings_path = args.ratings or newest_ratings_migration()
    print(f"  reading {ratings_path.name} ...", file=sys.stderr)
    rated = read_ratings(ratings_path)

    franchise_codes = {**load_av_franchise_codes(), **EXTRA_TEAM_CODES}
    pfr_ids = read_pfr_ids(read_csv(cached(PLAYERS_URL, "players.csv", args.refresh)))
    week_rows = []
    for season in range(FIRST_SEASON, LAST_SEASON + 1):
        week_rows.extend(read_csv(cached(WEEK_URL.format(season=season),
                                         f"stats_player_week_{season}.csv", args.refresh)))
    game_rows = read_csv(cached(GAMES_URL, "games.csv", args.refresh))
    print(f"  {len(rated):,} rated seasons, {len(week_rows):,} weekly rows, "
          f"{len(game_rows):,} games", file=sys.stderr)

    lines = qb_lines_from_weeks(week_rows, pfr_ids, franchise_codes)
    teams = team_seasons_from_games(game_rows, franchise_codes, FIRST_SEASON, LAST_SEASON)
    awards = read_awards(args.awards)

    seasons = real_seasons(rated, lines, teams, awards)
    model = fit(seasons, teams, config)

    try:
        run_guards(model, rated, teams, awards, seasons, config)
    except GuardFailure as failure:
        print(f"\nGUARD FAILED: {failure}", file=sys.stderr)
        if args.sample:
            print_summary(model, seasons, config)
        return 1
    print("  guards passed", file=sys.stderr)

    if args.sample:
        print_summary(model, seasons, config)
    if args.out:
        args.out.write_text(emit_sql(model, awards), encoding="utf-8")
        print(f"  wrote {args.out} ({args.out.stat().st_size / 1024:.0f} KB)", file=sys.stderr)
    return 0


if __name__ == "__main__":
    sys.exit(main())
