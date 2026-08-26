"""nflverse rosters.csv + Pro Football Reference roster pages -> sabotage
draft's roster pool.

This module is the one seam in the pool build: parsed source rows in, finished
`private.av_roster_players` records out. Everything that can be quietly wrong
lives here — position-vocabulary folding across eras, multi-position players,
franchise identity, and the AV-less/position-less exclusion rule. Fetching,
artifact writing and database loading stay outside it.

It is a pure function. No network, no filesystem, no clock, no globals a
caller cannot pass in — which is what makes rebuilds byte-identical, the same
requirement `scripts/player_pool/transform.py` carries for the same reason.

Two independent sources feed this, covering non-overlapping season ranges:

- nflverse's `nfldata/rosters.csv` (2006-2019), read with the standard `csv`
  module and passed in as dicts in its own column names.
- Pro Football Reference's `teams/{code}/{year}_roster.htm` pages (2020-),
  which cannot be fetched by a stdlib HTTP client (Cloudflare's JS challenge —
  see ../pfr_scrape.js) and are instead scraped once via a browser and cached
  to disk as compact pipe-delimited lines: `code|season|player_id|name|pos|av`.

Both sources key player identity on PFR's own id scheme directly — nflverse's
`playerid` column already uses it (e.g. `LeinMa00`), so there is no id
reconciliation between the two: a player who has rows in both sources carries
the same `player_id` in both.
"""

from collections import Counter
from typing import NamedTuple

# The ten roster-slot categories sabotage draft deals against. Four are
# skill positions with real fantasy stats elsewhere in this app; the other
# six exist only because AV is the one scale that prices them too.
SLOT_CATEGORIES = ("QB", "RB", "WR", "TE", "OL", "DL", "LB", "CB", "S", "ST")

# Every PFR position string this pipeline has actually seen, across both
# sources and all in-range seasons (2006-2019 from nflverse, 2020- from PFR
# directly) — verified against real fetched/downloaded rows, not guessed.
# Side/role encoding (`LCB`/`RCB`, `SS`/`FS`, `LOLB`/`RILB`, ...) persists
# essentially unchanged across the whole range; this table folds all of it
# onto the ten categories above.
#
# Deliberately absent: `DB`, PFR's own generic tag for "some kind of
# secondary" with no side or role recorded at all. Unlike every other
# generic-vs-side-encoded pair here (`CB` covers `LCB`/`RCB` the same way
# `LB` covers `MLB`/`OLB`), `DB` cannot be folded onto `CB` or `S` — PFR
# itself did not record which one the player was. See `_slot_for` for the
# exclusion this produces, rather than a guessed assignment.
POSITION_FOLD = {
    "QB": "QB",
    "RB": "RB", "FB": "RB", "HB": "RB",
    "WR": "WR",
    "TE": "TE",
    "T": "OL", "G": "OL", "C": "OL", "OL": "OL", "OT": "OL", "OG": "OL",
    "LT": "OL", "RT": "OL", "LG": "OL", "RG": "OL",
    "DE": "DL", "DT": "DL", "NT": "DL", "DL": "DL", "ED": "DL",
    "LDE": "DL", "RDE": "DL", "LDT": "DL", "RDT": "DL",
    "LB": "LB", "MLB": "LB", "OLB": "LB", "ILB": "LB",
    "LOLB": "LB", "ROLB": "LB", "LILB": "LB", "RILB": "LB",
    "LLB": "LB", "RLB": "LB", "MIKE": "LB", "SAM": "LB", "WILL": "LB",
    "CB": "CB", "LCB": "CB", "RCB": "CB",
    "S": "S", "SS": "S", "FS": "S",
    "K": "ST", "P": "ST", "LS": "ST", "ST": "ST", "KR": "ST", "PR": "ST",
}

# nflverse team code -> PFR's own stable franchise code, confirmed directly
# against PFR's franchise index (pro-football-reference.com/teams/index.htm):
# every relocated/renamed franchise keeps one code across its whole history
# (`oti` renders as the Oilers in 1975 and the Titans in 2023 alike), so this
# map exists only to translate nflverse's *different* abbreviation scheme onto
# PFR's, not to carry any relocation logic of its own. nflverse's 2006-2019
# rows already use the period-correct code for each season (`SD` through
# 2016, `LAC` from 2017), so both halves of a relocation appear on the left.
FRANCHISE_CODE = {
    "ARI": "crd", "ATL": "atl", "BAL": "rav", "BUF": "buf", "CAR": "car",
    "CHI": "chi", "CIN": "cin", "CLE": "cle", "DAL": "dal", "DEN": "den",
    "DET": "det", "GB": "gnb", "HOU": "htx", "IND": "clt", "JAX": "jax",
    "KC": "kan", "LAC": "sdg", "LAR": "ram", "MIA": "mia", "MIN": "min",
    "NE": "nwe", "NO": "nor", "NYG": "nyg", "NYJ": "nyj", "OAK": "rai",
    "PHI": "phi", "PIT": "pit", "SD": "sdg", "SEA": "sea", "SF": "sfo",
    "STL": "ram", "TB": "tam", "TEN": "oti", "WAS": "was",
}


class RosterRow(NamedTuple):
    """One row of `private.av_roster_players`, in column order."""

    franchise_code: str
    season: int
    player_id: str
    display_name: str
    slot_category: str
    av: int


def transform(nflverse_rows, pfr_lines):
    """Turn both sources' raw rows into finished roster rows.

    `nflverse_rows` are `csv.DictReader` dicts over `nfldata/rosters.csv`'s own
    columns. `pfr_lines` are the cached scrape's raw text lines, each
    `code|season|player_id|name|pos|av`.

    Returned rows are sorted by season, franchise, then player id, which is
    what makes two runs over the same input byte-identical.
    """
    out = []
    seen = set()

    for row in nflverse_rows:
        record = _from_nflverse(row)
        if record is None:
            continue
        out_row = _finish(*record)
        if out_row is None:
            continue
        key = (out_row.franchise_code, out_row.season, out_row.player_id, out_row.slot_category)
        if key in seen:
            continue
        seen.add(key)
        out.append(out_row)

    for line in pfr_lines:
        record = _from_pfr_line(line)
        if record is None:
            continue
        out_row = _finish(*record)
        if out_row is None:
            continue
        key = (out_row.franchise_code, out_row.season, out_row.player_id, out_row.slot_category)
        if key in seen:
            continue
        seen.add(key)
        out.append(out_row)

    out.sort(key=lambda r: (r.season, r.franchise_code, r.player_id))
    return out


# --------------------------------------------------------------- adapters --


def _from_nflverse(row):
    """One `nfldata/rosters.csv` row -> (code, season, player_id, name, pos, av),
    or None if the row carries nothing this pool can use.

    Blank `position` (about 31% of the file — players with no recorded snaps
    at all: `games`, `starts` and `av` all zero) is excluded outright, the
    same way a blank AV is: there is nothing here to place into a slot.
    """
    pos = (row.get("position") or "").strip()
    if not pos:
        return None
    av = (row.get("av") or "").strip()
    if av == "":
        return None
    code = FRANCHISE_CODE.get(row["team"])
    if code is None:
        return None
    return (code, int(row["season"]), row["playerid"], row["full_name"], pos, av)


def _from_pfr_line(line):
    """One cached scrape line -> (code, season, player_id, name, pos, av),
    or None for a malformed line."""
    parts = line.split("|")
    if len(parts) != 6:
        return None
    code, season, player_id, name, pos, av = parts
    if not pos or av == "":
        return None
    return (code, int(season), player_id, name, pos, av)


# -------------------------------------------------------------- finishing --


def _slot_for(pos):
    """The governing slot category for a (possibly multi-position) PFR
    position string, or None if it can't be placed.

    Multi-position strings are split on both `/` (the modern separator,
    `RG/LG`) and `-` (`T-G`, seen in the 2020-2025 scrape) and the
    first-listed segment governs — a single documented rule applied
    uniformly, rather than a per-player judgment call about which listed
    position is "primary". `DB` and anything else outside `POSITION_FOLD`
    (there is nothing else in range) returns None: excluded, not guessed.
    """
    first = pos.replace("-", "/").split("/")[0].strip()
    return POSITION_FOLD.get(first)


def _finish(code, season, player_id, name, pos, av):
    slot = _slot_for(pos)
    if slot is None:
        return None
    return RosterRow(
        franchise_code=code,
        season=season,
        player_id=player_id,
        display_name=name,
        slot_category=slot,
        av=int(av),
    )


# ------------------------------------------------------------------ notes --


def coverage(rows):
    """(franchise_code, slot_category) pairs with at least one row.

    Used by the build's guards to catch an empty cell — a franchise/slot
    combination the game needs that turned up with nobody in it.
    """
    return Counter((r.franchise_code, r.slot_category) for r in rows)
