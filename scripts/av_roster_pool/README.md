# AV roster pool

Sabotage draft's pool: every rostered player, every franchise, 2006 through
2025, across all fourteen roster slots via ten slot categories (QB/RB/WR/TE
plus OL/DL/LB/CB/S/ST), priced on one scale — Approximate Value (AV) — so a
Hall of Fame guard and a Hall of Fame receiver compare on the same number.
Game rules in
[`docs/games/sabotage_draft.md`](../../docs/games/sabotage_draft.md); the
full scoping behind this pool's shape and era floor is in
[`docs/games/sabotage_draft_data_scoping.md`](../../docs/games/sabotage_draft_data_scoping.md).

A sibling to [`scripts/player_pool/`](../player_pool/), and meaningfully
heavier: two sources instead of one, a franchise-identity translation step
neither needs, and a fetch step that a stdlib script cannot run on its own.

## Loading it

```sh
supabase db push
```

Same as the existing pool: the table and its rows both arrive as migrations
(`0049` creates `private.av_roster_players`, `0050` fills it), so a fresh
clone reaches a loaded database in one command.

## Why 2006, not 1985

1985 was the first candidate, fully scoped in
[`sabotage_draft_data_scoping.md`](../../docs/games/sabotage_draft_data_scoping.md).
It was walked back once the live-scrape cost became concrete: everything
2006-2019 is free, no-scraping data (`nfldata/rosters.csv`, below), so a 2006
floor confines the *only* live scrape this pool needs to 2020-2025 — about
192 team-season pages instead of the ~780 a 1985 floor would have needed
(1985-2005 *and* 2020-present, both requiring a live scrape). That's a real
trade, made deliberately: it drops 1985-2005 entirely, including the deep-cut
names that window would have kept (Marino's early prime, Walter Payton's
final seasons, Lawrence Taylor, Reggie White's debut, the '85 Bears itself).

## Two sources, one pipeline

**2006-2019 — `nfldata/rosters.csv`, free, no scraping.** nflverse's legacy
roster dataset happens to have exactly this pool's schema already, AV
included. It hasn't been updated since September 2019, which is exactly why
it only covers this half of the range.

**2020-2025 — a cached Pro Football Reference scrape.** PFR is the *only*
source for AV outside that stale file (AV is PFR's own invented metric — no
independently-computed alternative exists anywhere), and PFR cannot be
fetched by this script directly: it sits behind a Cloudflare JS challenge no
stdlib HTTP client can pass. See [`pfr_scrape.js`](./pfr_scrape.js) for the
browser-console procedure that produces the cache file
`build_pool.py` reads (`--pfr-cache`, default `.cache/pfr_2020_2025.txt`).
This is a one-time manual step, not something `build_pool.py` can run itself
— budget real time for it (paced under PFR's 20-requests/minute limit, ~192
team-seasons takes under 10 minutes of actual fetching).

Both sources key player identity on PFR's own id scheme directly — nflverse's
`playerid` column already uses it — so a player who has rows in both sources
needs no id reconciliation between them.

## Rebuilding it

You do not need to. The seasons are frozen history and the artifact is
checked in. Rebuild only when extending the era range — say, adding a newly
completed season:

```sh
# 1. Extend pfr_scrape.js's SEASONS, run it in a browser tab per its own
#    header comment, and save the result to .cache/pfr_<first>_<last>.txt

# 2. Build the migration
python3 scripts/av_roster_pool/build_pool.py \
  --pfr-cache scripts/av_roster_pool/.cache/pfr_<first>_<last>.txt \
  --out supabase/migrations/<timestamp>_00xx_av_roster_players_<range>.sql
```

**Never regenerate an applied migration.** Same rule as the existing pool:
migration history is append-only, so a new season is a new file.

## Position-vocabulary folding

Verified directly against both sources, not assumed: side/role-encoded
position strings (`LCB`/`RCB`, `SS`/`FS`, `LOLB`/`RILB`, ...) appear
essentially unchanged from 2006 through the 2020-2025 scrape — this doesn't
get materially cleaner at the modern end. `transform.POSITION_FOLD` maps
every string either source actually produces onto the ten slot categories.
Multi-position strings (`RG/LG`, and — only in the 2020-2025 scrape — the
hyphenated `T-G`) resolve by one rule, applied uniformly: the first-listed
position governs.

**`DB` — PFR's own generic "some kind of secondary" tag — is excluded, not
guessed.** Unlike every other generic/side-encoded pair here, there's no
side information to fold onto `CB` or `S`: PFR itself didn't record which one
the player was. This drops roughly 5% of the 2020-2025 scrape and about 1% of
the 2006-2019 file — a real, deliberate, and small cost of not eyeballing an
assignment PFR didn't make.

A blank position (about 31% of the nflverse file — players with zero
recorded games, starts, and AV) and a blank AV (present but position-bearing
rows, no AV computed) are both excluded outright, the same way an AV-less
row would be for any other reason: nothing to place, not worth guessing.

## Shape

```
build_pool.py    fetch (nflverse auto; PFR from a pre-made cache), guards, artifact
transform.py     the seam: both sources' raw rows -> finished roster rows
test_transform.py
pfr_scrape.js    the browser-console procedure that makes the PFR cache
```

`transform` is the only unit-tested piece, for the same reason as the
existing pool: it's the only piece that can be quietly wrong — position
folding, franchise identity, multi-position resolution, exclusions.
Fetching and file writing either work or crash loudly.

```sh
python3 -m unittest discover scripts/av_roster_pool
```

The build's own **guards** run over the real output and fail the build
rather than warn: every `(franchise_code, slot_category)` pair the game
needs is non-empty, no duplicate primary key, every row's slot category and
franchise code are ones the schema actually accepts, AV sits within a
generous sanity bound (real AV can be negative — confirmed in the source, a
handful of quarterbacks and kickers score a single-digit negative AV season;
the bound exists to catch a parsing error, not to second-guess PFR's own
metric), and a transform that disagrees with itself across two differently-
shuffled runs.

## Notes

**Why `private`, and why not a `sabotage_draft`-specific schema.** This is a
content pool, the same kind of thing `player_weeks` already is — not one
game's own state — so it lives in the same shared `private` schema rather
than a new `sabotage_draft_private`. AV must stay unreadable by the client
until a round resolves the same way fantasy points do; a table with no
REST-exposed schema at all is what makes that true unconditionally, not a
policy that could later be loosened by accident.

**Franchise identity.** `transform.FRANCHISE_CODE` translates nflverse's team
abbreviations onto PFR's own stable per-franchise codes (confirmed directly
against PFR's franchise index: one code survives every relocation and
rename — `oti` renders as the 1975 Oilers and the 2023 Titans alike). The
2020-2025 scrape already carries PFR's codes directly, so only the nflverse
half needs translating.

**Licensing is unreviewed, more so than the existing pool's.** nflverse's own
posture already wants a legal read before wide release; PFR's Terms of Use
are explicitly more restrictive — among other things, prohibiting a data
store that "constitutes a material substitute for" PFR's own services. This
pool is a derived (franchise, season, slot) -> (player, AV) table for
gameplay, a different shape than that, but the same kind of pre-playtest
legal read nflverse's data got is owed here too, more urgently.
