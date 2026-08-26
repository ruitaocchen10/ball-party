# Sabotage draft — data scoping

Answers the load-bearing open question in
[`sabotage_draft.md`](./sabotage_draft.md): is the OL/DL/LB/CB/S/ST + AV
pipeline even buildable, and what would it look like? Everything here was
checked against a primary source — real fetched Pro Football Reference (PFR)
pages, PFR's own methodology page, PFR's own Terms/data-use pages, and actual
files pulled from nflverse's GitHub releases — not a secondary write-up of any
of these. Where I could not verify something against a fetched page, it's
flagged as such rather than stated as fact.

## 1. Source availability & structure

PFR does publish exactly the page type the design doc assumes, at exactly the
URL pattern named: `pro-football-reference.com/teams/{code}/{year}_roster.htm`.
Confirmed by fetching three real examples with a real browser (the site sits
behind a Cloudflare JS challenge — see §4 — so this had to be a rendered page,
not a raw HTTP fetch):

- `teams/kan/2023_roster.htm` — 2023 Kansas City Chiefs
- `teams/pit/1975_roster.htm` and `teams/oti/1975_roster.htm` — 1975 Steelers
  and 1975 Houston Oilers
- `teams/gnb/1921_roster.htm`, `.../1950_roster.htm`, `.../1953_roster.htm`,
  `.../1956_roster.htm`, `.../1958_roster.htm`, `.../1959_roster.htm`,
  `.../1960_roster.htm` — Packers across seven eras, used to pin down exactly
  where AV coverage starts
- `teams/chi/1959_roster.htm` — Bears, to check the AV cutoff isn't
  Packers-specific

**Columns present, read directly off the rendered table's `data-stat`
attributes (not just the visible text):** `uniform_number`, `player`, `age`,
`pos`, `g` (games), `gs` (games started), `weight`, `height`, `college_id`,
`birth_date_mod`, `experience` (`Yrs`), `av`, `draft_info`. Position and AV sit
in the same row of the same table — the design doc's core assumption holds.
There's also a separate `starters` table above the full roster, one row per
starting slot, which is not what the pipeline would read but confirms the
Pos labeling PFR itself uses for starter slots (see below).

**Position encoding is not stable across eras — this is a real finding, not
a guess.** The 2023 Chiefs roster uses simple generic codes: `QB`, `RB`, `WR`,
`TE`, `T`, `G`, `C`, `OL` (a generic lineman tag for players who moved between
line spots), `DE`, `DT`, `NT`, `LB`, `CB`, `S`, `DB` (generic secondary), `K`,
`P`, `LS`. The 1975 Steelers/Oilers rosters instead encode side and sometimes
role directly into the position string in the *same* roster table: `LCB`,
`RCB`, `LDT`, `RDT`, `LDE`, `RDE`, `LLB`/`MLB`/`RLB` or `LOLB`/`LILB`/`RILB`/
`ROLB`, `SS`, `FS`, `LT`, `LG`, `RG`, `RT`. A build script cannot treat "CB" as
the canonical string across the whole history — it has to fold `LCB`/`RCB`
into `CB`, `SS`/`FS` into `S`, etc., and that folding table itself has to
change shape across eras (`MLB` vs `MIKE`-style naming, `LDT`/`RDT` vs plain
`DT`, and so on). The 1921 Packers roster goes further back still, using
period positions with no modern equivalent at all: `HB`, `TB`, `E`, `FB-HB`,
`E-HB`, `G-T` (literal multi-position slash-strings, not a coding artifact —
see §5).

**AV is present structurally at every era but empirically absent before
1960 — confirmed by reading the actual DOM cells, not just the visible
text.** I pulled every player row's `av` cell value directly via JS for
several Packers seasons and one Bears season:

| Season | Team | Players with a non-blank AV |
| ------ | ---- | ---------------------------- |
| 1921 | GNB | column exists, all blank |
| 1950 | GNB | 0 / 36 |
| 1953 | GNB | 0 / 40 |
| 1956 | GNB | 0 / 40 |
| 1958 | GNB | 0 / 38 |
| 1959 | GNB | 0 / 37 |
| 1959 | CHI (Bears) | 0 / 40 |
| 1960 | GNB | 39 / 39 |

The cutoff between 1959 and 1960 is exact and it isn't team-specific (Bears
confirm it). This matches PFR's own methodology page in their words, not
mine: **"an attempt to put a single number on the seasonal value of a player
at any position from any year (**since 1960**)"** — fetched from
`pro-football-reference.com/about/approximate_value.htm`. That same page is
worth reading before finalizing a cutoff year, because AV's own formula
changes inputs mid-history in ways that matter for cross-era comparison: the
defensive formula only starts counting tackles in 1994 (`tkl_constant = 0` for
"the year is before 1994"), and the "post-sack years" multiplier splits at
1982 (official sacks weren't tracked 1960–1981). So AV going back to 1960 is
real, but a 1962 AV and a 2023 AV for a defensive lineman are not built from
the same raw ingredients — the metric itself absorbed the eras' different
data richness, which is presumably by design (Drinen's own caveat on that page
is that AV was never meant to distinguish finely between two similar seasons)
but worth knowing before treating it as one flat scale for game balance.

**How far back rosters go before thinning:** even the 1921 Green Bay roster —
the earliest team file that exists — renders fully with weight/height/college/
birthdate for most players, just with no AV and a much smaller table (25
players vs. ~40 for a mid-century team vs. ~60+ for a modern team, roster
sizes having grown over the league's history). I did not check every decade
back to 1920 for every franchise, but nothing suggests these tables disappear
before 1920 — 1920/1921 is simply where the league's first season is, per the
franchise index (§2).

## 2. Team identity across history

PFR unifies relocations and renames under a single franchise history itself —
the pipeline would not need to build this mapping from scratch. Confirmed by
fetching `pro-football-reference.com/teams/index.htm`, the franchise index:
every relocated/renamed franchise appears as one continuous top-level row
(with a franchise-wide win/loss record spanning every name it ever had) and
then nested sub-rows for each named era. Examples pulled directly off that
page:

- **Cardinals**: one `Arizona Cardinals 1920–2026` row nests `Chicago
  Cardinals 1920–1943`, `Chi/Pit Cards/Steelers 1944` (the WWII-era merged
  "Card-Pitt" team), `Chicago Cardinals 1945–1959`, `St. Louis Cardinals
  1960–1987`, `Phoenix Cardinals 1988–1993`, `Arizona Cardinals 1994–2026`.
- **Oilers → Titans**: one `Tennessee Titans 1960–2026` row nests `Houston
  Oilers 1960–1996`, `Tennessee Oilers 1997–1998`, `Tennessee Titans
  1999–2026`.
- **Raiders**: one `Las Vegas Raiders 1960–2026` row nests `Oakland Raiders
  1960–1981`, `Los Angeles Raiders 1982–1994`, `Oakland Raiders 1995–2019`,
  `Las Vegas Raiders 2020–2026`.
- **Rams**: one `Los Angeles Rams 1937–2026` row nests `Cleveland Rams
  1937–1945`, `Los Angeles Rams 1946–1994`, `St. Louis Rams 1995–2015`, `Los
  Angeles Rams 2016–2026`.

More importantly, **the franchise keeps one stable team code across every
name/city era**, and roster URLs use that code, not a per-era one — this is
the load-bearing part for a pipeline. Verified directly, not inferred from
the index page: `teams/oti/1975_roster.htm` renders as the *1975 Houston
Oilers* (title tag confirms it), and `teams/ram/1975_roster.htm` renders as
the *1975 Los Angeles Rams* — same code family a modern-day fetch of that
franchise would use. I spot-checked these two codes directly; I did not
independently fetch-verify `crd` (Cardinals) or `rai` (Raiders) the same way,
though the franchise-index nesting behavior for those two looks structurally
identical, so I'd expect the same stable-code pattern to hold — flagging that
as inferred-not-fetched rather than confirmed.

Net: a build script keys off PFR's own 3-letter franchise code as the team
identity for a season, and does not need to reimplement relocation/rename
mapping — PFR already carries "who is this franchise this year" as data. The
one thing the pipeline *does* still own is mid-season trades within a single
season (a player who suits up for two franchises in the same year) — PFR's
roster page for a team-season only lists players who played *for that team*
that year, so a traded player legitimately appears on both team's rosters for
that season, each with a partial-season AV. That's a real edge case for "any
team, any year" pick logic, not a franchise-identity problem.

## 3. Scale

This is a rough order-of-magnitude estimate from the roster sizes actually
observed above, not a page-by-page count — flagging it as an estimate, not a
verified total.

Observed roster-table row counts: 1921 GNB ≈ 25, 1950/1959 GNB ≈ 36–37, 1975
PIT/OTI ≈ 41 each, 2023 KC ≈ 63 (modern rosters run bigger, reflecting more
in-season roster churn getting recorded than PFR's older team-season tables
show).

| Era cutoff | Seasons | Approx. teams/season | Team-seasons | Rows @ ~45/team-season (older-era assumption) | Rows @ ~55/team-season (mixed-era assumption) |
| --- | --- | --- | --- | --- | --- |
| Since 1970 (merger) | 56 (1970–2025) | ~28 avg (26→32) | ~1,550 | ~70,000 | ~85,000 |
| Since 1990 | 36 (1990–2025) | ~29 avg (28→32) | ~1,050 | ~47,000 | ~58,000 |
| Since 2000 | 26 (2000–2025) | ~31 avg (31→32) | ~810 | ~36,000 | ~45,000 |
| Since 1960 (AV's own floor) | 66 (1960–2025) | ~24 avg (8 AFL+13 NFL→32) | ~1,900 | ~85,000 | ~105,000 |

For comparison, `scripts/player_pool/README.md` describes the existing pool as
2010–2025 (16 seasons), 4 skill positions, weekly granularity. That pool's
*player-season* count (the unit AV rows would use, since AV is a per-season
number, not per-week) is on the order of 32 teams × ~10–12 rostered
skill-position players × 16 seasons ≈ 5,000–6,000 player-seasons. Any
reasonable AV-pool cutoff — even the tightest, since-2000 — is roughly
**6–8x more player-season rows** than the existing pool, covering **7 of 14
roster slots instead of 4 of 6**, over more than the existing pool's era
range. Going back to 1970 or 1960 pushes that multiple higher still. This is
a genuinely bigger pipeline, not a same-size sibling.

## 4. Access method & constraints

**No API, no bulk export.** Confirmed on PFR's own data-use page
(`sports-reference.com/data_use.html`, which is Sports Reference's site-wide
policy and explicitly covers Pro Football Reference): *"Most of our data
comes from third parties who sell the data to us. As part of our agreements
with them we can not provide the data available as a download on our site.
We are aware that an API would mitigate some issues, but it's not our
business model."* Custom data requests are explicitly priced at **"a
minimum of $5,000"** per the same page.

**robots.txt does not blanket-block scraping, but it does block AI
crawlers and some paths.** Fetched `pro-football-reference.com/robots.txt`
directly (note: it sits behind the same Cloudflare challenge as the roster
pages — a plain `curl` gets an interstitial "Just a moment..." page and never
reaches robots.txt itself; only a real browser session got the actual file).
Contents relevant here: `GPTBot` is fully disallowed (`Disallow: /`),
`AhrefsBot`/`SlySearch` are fully disallowed, and the generic `User-agent: *`
block disallows `/football/`, search endpoints, `/my/`, and a long list of
per-player sub-pages (`splits`, `gamelog`, `fantasy`, `touchdowns`, etc.) —
**`/teams/{code}/{year}_roster.htm` is not on that disallow list.** So
robots.txt itself doesn't forbid fetching roster pages for a generic
user-agent; the constraint is elsewhere.

**Explicit rate limit, stated in numbers, on Sports Reference's own bot-traffic
page** (`sports-reference.com/bot-traffic.html`, updated May 2024): *"we will
block users sending requests to... our other sites** [PFR is one of these,
distinct from FBref/Stathead] **more often than twenty requests in a
minute... regardless of bot type and construction... If you violate this rule
your session will be in jail for up to a day."* Twenty requests/minute is a
real, load-bearing number for how a build script should be paced.

**Cloudflare's managed JS challenge is a practical, not just a policy,
barrier.** A plain `curl` (even with a realistic desktop User-Agent) to
`robots.txt` and to a real roster page both returned a Cloudflare
"Just a moment..." interstitial rather than the actual content — this is not
a robots.txt disallow, it's an active bot-detection layer that a plain HTTP
client cannot pass. Every fetch in this document that succeeded went through
a real rendered browser session (which Cloudflare let through after a few
seconds, no CAPTCHA solve needed in this session's case), not a raw HTTP
request. **A one-time or periodic build script would need something that
executes JavaScript and holds a session** (headless Chrome/Playwright, or a
library that already handles the challenge) — a bare `requests`/`urllib`
script will not get past this on its own. This is worth calling out as a real
build-complexity cost beyond "just fetch the page," distinct from the
skill-position pipeline's plain-CSV nflverse-data downloads.

**Content-reuse restriction, separate from the rate limit.** Sports
Reference's Terms of Use (referenced from the same data-use page) explicitly
prohibit, among other things: building "any database, archive, or other data
store that competes with or constitutes a material substitute for" PFR's own
services, and using PFR content "for purposes of training, fine-tuning,
prompting, or instructing artificial intelligence models... in any manner."
A game that stores derived (team, position, year) → (player, AV) rows for
gameplay is a different use case than either of those two prohibited ones,
but it's still explicitly "automated means to access... the Site... without
our express written permission" per the same clause — the same posture the
`player_pool/README.md` already flags for nflverse ("Licensing is
unreviewed... the terms want reading before this is in front of anyone
outside a playtest"), except PFR's terms are considerably more explicit and
restrictive than nflverse's public-data stance. This deserves the same kind
of pre-playtest legal read nflverse got, probably more of one.

**Community tooling exists and covers roster+AV scraping already**, found via
search, not independently vetted line-by-line:
[`mjk2244/pro-football-reference-web-scraper`](https://github.com/mjk2244/pro-football-reference-web-scraper)
(also on PyPI), [`tefirman/sportsref-nfl`](https://github.com/tefirman/sportsref-nfl)
(a CLI with an explicit `rosters --year --team` command),
[`blnkpagelabs/nflscraPy`](https://github.com/blnkpagelabs/nflscraPy), and a
few smaller one-off scripts (`BenKite/football_data`, `ewelchman/scrape_pfr`).
None of these were fetched and inspected as primary sources here — they're
existence claims from search results only, flagged as unverified starting
points a build script could evaluate, not confirmed-working solutions.

**nflverse itself has a partial, but stale, alternative — checked against
the actual files, not documentation claims.** `nflverse/nfldata`'s
`DATASETS.md` (fetched raw from GitHub) documents a `rosters.csv` dataset,
sourced from PFR, with exactly the columns this game needs: `season`, `team`,
`category` (`OL`/`QB`/`RB`/`TE`/`WR` offense, `DB`/`DL`/`ED`/`LB` defense,
`K`/`KR`/`LS`/`P`/`ST` special teams), `position`, `games`, `starts`,
`years`, and **`av`** ("The player's Approximate Value that year, as defined
by the Pro Football Reference metric"). I fetched the actual CSV
(`raw.githubusercontent.com/leesharpe/nfldata/master/data/rosters.csv` — this
repo now redirects to `nflverse/nfldata`, confirmed via the GitHub API) and
it's real: 28,618 rows, seasons 2006 through 2019 only, `av` column populated
with real numbers (e.g., 2006 Matt Leinart QB ARI, av=8). **This file has not
been updated since September 3, 2019** (confirmed via the GitHub commits API
against that exact path) — it stops mid-way through what should be a 2019
season and was never extended to 2020+. It is a *different, legacy* dataset
from the actively-maintained `nflverse-data` GitHub-release pipeline (the
`rosters` release tag there, which powers `nflreadr::load_rosters()`, is a
separate NFL.com/gsis-sourced feed going back to 1920 with jersey numbers,
draft club, `status` (ACT/CUT/INA), etc. — I fetched `roster_1920.csv` and
`roster_2023.csv` directly from that release and **neither has an `av`
column at all**). So: nflverse does carry a real, PFR-sourced AV+full-position
roster dataset, but it is frozen at 2006–2019, lives outside the pipeline the
rest of this repo already depends on, and isn't reachable through the loader
functions (`load_rosters()`, `load_players()`, etc.) that would normally be
reached for for this kind of data — it would have to be pulled from that
specific stale CSV directly, then extended by scraping PFR for everything
before 2006 and after 2019.

## 5. Build shape

A `scripts/av_roster_pool/` sibling to `scripts/player_pool/` is plausible,
but its shape is dictated by everything above, and it's a meaningfully
heavier build than the skill-position pool:

**Fetch.** Either (a) scrape PFR's `teams/{code}/{year}_roster.htm` pages
directly, which requires a JS-capable fetcher (§4) paced under ~20
requests/minute with caching so a re-run doesn't re-hit already-fetched
seasons, or (b) start from nflverse's stale 2006–2019 `nfldata/rosters.csv`
for that window (no scraping needed, already has `av`) and scrape PFR
directly only for the years that CSV doesn't cover — everything before 2006,
and everything 2020 onward. Option (b) shrinks the scraping surface
substantially (roughly the 2020–2025 seasons plus whatever pre-2006 depth is
wanted) at the cost of running two different code paths that have to agree on
schema. Given §3's scale numbers, even a "since 2000" cutoff means scraping
~500+ team-season pages that aren't in the stale CSV; going back to 1970 or
1960 means several times that.

**Normalize.** This is where the judgment calls concentrate, and every one of
them is visible in the pages already fetched above, not hypothetical:
- **Position-string folding across eras** — `LCB`/`RCB` → `CB`, `SS`/`FS` →
  `S`, `LDT`/`RDT`/`NT` → `DT`-family, `LOLB`/`LILB`/`RILB`/`ROLB` →
  linebacker slots, down to 1920s strings like `HB`/`TB`/`E` that don't map
  cleanly onto any of this game's 6 non-skill slots at all and need an
  explicit decision (exclude the player? force a best-guess mapping? cut off
  the pool before positions get this exotic?).
- **Multi-position players, encoded directly in PFR's own `pos` string** —
  real examples pulled above: `RG/LG` (Sam Davis, 1975 PIT), `MG/C` (Ed Neal,
  1950 GNB), `RT/RDT` and `LT/LDT` (Joe Spencer, Dick Wildung, 1950 GNB),
  `E-HB`, `FB-HB`, `G-T` (1921 GNB). A player like this needs a rule for
  which of this game's roster slots he's eligible for — first-listed, all
  listed, or primary-by-games-started — and that rule has to be decided
  once and applied consistently, not eyeballed per player.
- **Team attribution for a traded player** — as noted in §2, a mid-season
  trade means a player-season can legitimately appear on two team rosters
  with two different partial-season AVs; the sabotage draft's "any player
  from that team's history" pick needs a decision on whether a half-season
  stint counts as "played for that team," and if so, whether the AV shown is
  the partial-season number PFR already computed for that stint or something
  reconciled.
- **AV's own era-dependent inputs** (§1) — a defensive back's AV in 1965 and
  in 2023 are not built from comparable raw stats (tackles only count from
  1994 on, sacks only official from 1982 on). Nothing in the design doc
  currently asks the pipeline to correct for this, and PFR doesn't either —
  it's presented as one continuous number — but it's worth the game's
  designers knowing the number quietly gets more information-rich as the
  eras get more recent, which may already be fine given AV was never meant
  to be finely discriminating (Drinen's own words, quoted in §1).
- **Era cutoff choice** — 1960 is AV's own hard floor (§1), but 1960s/70s
  rosters are smaller (~40 vs. ~60 modern) and use the least game-friendly
  position vocabulary (§1, §5's first bullet), so a narrower cutoff (1990 or
  2000) trades away real history depth for cleaner, more game-recognizable
  positions and names — the same "deep tier stays recognizable" instinct the
  skill-position pool's tier tuning already leans on.

**Store.** Given the scale in §3 and this repo's existing pattern (frozen
history, checked-in migration, `private` schema so AV doesn't leak
pre-reveal the way points don't) — a per-position (or per-side) table
keyed on `(franchise_code, season, player_id)` mirroring
`private.player_seasons`'s shape is the natural fit, with a `slot_category`
column (`OL`/`DL`/`LB`/`CB`/`S`/`ST`, from PFR's own `category`-equivalent) so
the sabotage draft's "spin a team, pick from its history at this slot" query
is a straight filter, the same way the auction's tiering already reads off a
precomputed column rather than deriving it at query time.

## Era cutoff: is 1985 a good starting point?

Checked directly against fetched pages (Bears and Dolphins 1985 rosters, plus
Bears 1994/2000/2010/2018/2023 as a trend line), not inferred from the 1960s/
70s/2020s samples in §1 alone.

**AV is fully populated in 1985 — confirmed, not assumed.** Bears 1985: 49/49
players with a non-blank AV. Dolphins 1985: 56/56. No gap, as expected given
§1 already put the AV floor at 1960 — 1985 is well inside it.

**1985 does not dodge the position-folding problem — this corrects an
assumption worth naming before it hardens into the plan.** The 1985 Bears and
Dolphins rosters both still use the same side/role-encoded vocabulary as the
1975 sample in §1: `LCB`/`RCB`, `SS`/`FS`, `LDE`/`RDE`/`LDT`/`RDT`, `LOLB`/
`LILB`/`RILB`/`ROLB`, `LG`/`RG`/`LT`/`RT`. Multi-position slash-strings also
still occur (Bears 1985 has a `LDE/RDT` case, same shape as the 1975 examples
in §5). Pulling the trend forward year by year on the same franchise (Bears)
shows this encoding is not an artifact of the 1970s specifically — it persists
almost unchanged through 1994, 2000, 2010, and 2018, all of which came back
fully side-encoded (`LCB`/`RCB`, `LOLB`/`RILB`, etc.) with zero generic-only
rosters among them. Only the 2023 Bears roster shows real movement toward
generic codes (`LB`, `DL`, `DB`, `OL`, `CB`, `S` alongside `QB`/`WR`/`TE`/`RB`)
— and even that roster still mixes in a few side-encoded stragglers (`LG`,
`RDT`, `RT`) on the same page. So the position-vocabulary normalization work
this doc already scoped in §5 is required across essentially the *entire* AV
era, not something a 1985 (or even a 2010) cutoff meaningfully lightens. It
only gets close to clean at the current-day end, and not fully even then.

**AV's own tackle-counting change (1994) sits *inside* a 1985 window, not
before it.** §1 already noted the defensive AV formula only counts tackles
from 1994 on and only counts official sacks from 1982 on. A 1985 cutoff is
comfortably after the 1982 sack change (so 1985+ defensive AV has official
sack data throughout), but it opens 9 seasons (1985–1993) that sit in the
tackle-less regime before crossing into the tackle-counting one at 1994 —
that seam is now a real internal feature of an in-scope range, not an
excluded pre-history detail. A cutoff at 1994 itself would remove that seam
entirely, at the cost of the 1985–1993 seasons' name recognition (Marino's
early prime, Walter Payton's final years, Lawrence Taylor, Reggie White's
debut, the '85 Bears themselves).

**Roster sizes are healthier than the 1970s sample, still smaller than
today's.** Bears 1985: 49 rostered players. Dolphins 1985: 56. Compare to the
1975 sample's ~41 (§3) and the 1921 sample's ~25, versus 2023's ~60–68. 1985
sits in a comfortably fuller band than the 1970s did — more names per
team-season to pick from.

**Scale, recomputed for this specific range using real NFL team-count
history** (28 teams 1976–1994, 30 from 1995, 31 from 1999, 32 from 2002) and
the roster sizes actually observed above (not the older §3 table's more
conservative 45/row assumption, since 1985 rosters already run ~50–56):
1985–2025 is 41 seasons ≈ **1,261 team-seasons**, versus §3's ~1,050 for
since-1990 and ~1,550–1,900 for since-1970/1960. At ~50–60 rows/team-season,
that's roughly **63,000–76,000 player-season rows** — meaningfully more than
a since-2000 pool (~36–45k) and only modestly lighter than since-1970
(~70–85k), because most of 1970–1984's extra seasons fall in the same
28-team era 1985 already sits in.

**Net read:** 1985 is a defensible middle ground, but pick it for the right
reason. It's not lighter to build than 1970 in the way it might sound —
scale drops only ~25% and the position-vocabulary work is identical either
way. What it actually buys is roster-depth health (fuller rosters than the
70s) and a specific slice of recognizable history (mid-80s through today)
at a real but not dramatically smaller scale than going back to the merger.
If the goal is dodging AV's own internal seam, 1994 is the clean cutoff, not
1985. If the goal is maximum recognizable "deep cut" depth for the fewest
extra rows, 1985 versus 1990 is a small trade (~200 extra team-seasons) for
five more years of history — worth it on those terms alone.

## Revised era cutoff: 2006, not 1985

The analysis above stands as the record of why 1985 was the first call and
what it traded off. It was walked back once the build cost stopped being an
estimate and became a concrete decision in front of an actual implementation
ticket. The relevant fact, not present above because it wasn't yet load-
bearing: `nfldata/rosters.csv` (§4) is a **complete, free, no-scraping**
source for 2006–2019 — every column this pipeline needs, AV included, zero
requests against PFR itself.

That changes the shape of the tradeoff entirely. A 1985 floor means scraping
PFR directly for two separate windows — 1985–2005 and 2020–present — roughly
588 + 192 ≈ **780 team-season pages**, all behind Cloudflare's JS challenge,
all paced under PFR's stated 20-requests/minute limit (§4), all under Terms
of Use that are explicit and unreviewed about automated access. A 2006 floor
needs the scrape for **2020–present only — roughly 192 team-season pages**,
about a quarter the exposure, comfortably under 10 minutes of fetching at the
rate limit instead of 40+. The position-vocabulary folding work (§5) is
unchanged either way — 2006–2019 rows already carry the older side-encoded
strings, so this cutoff doesn't buy simpler normalization, only less scraping.

It also incidentally clears the one internal seam a 1985 floor opened on its
own: AV's defensive formula only starts counting tackles in 1994 (§1), so a
2006 floor sits entirely past that change — every in-range season's
defensive AV is built from the same inputs, where 1985's 1985–1993 slice
would not have been.

The cost is real and worth stating plainly rather than downplaying: this
drops the 1985–2005 window entirely, including the names the "Net read"
above called out as 1985's actual case — Marino's early prime, Walter
Payton's final seasons, Lawrence Taylor, Reggie White's debut, the '85 Bears
itself. This was a deliberate call to shrink scraping surface and PFR
exposure once that cost had a real number attached to it, not a claim that
2006 is a *better* cutoff on recognizability grounds — 1985 still wins that
comparison. It's a smaller, faster, lower-exposure build in exchange for
losing real history depth.

## Bottom line for the open question

The pipeline is buildable — PFR really does publish position+AV together at
the named URL pattern, really does unify franchise history under stable
codes, and nflverse really does have a partial AV+non-skill-position dataset
to lean on for 2006–2019. But it is not a small second pipeline: it's several
times the row count of the existing skill-position pool, it needs a
JS-capable, rate-limited scraper the existing nflverse-CSV pipeline never
needed, it inherits PFR's explicit anti-reuse terms on top of nflverse's
already-unreviewed licensing, and its normalization step (era-dependent
position strings, multi-position players, mid-season trades, an AV metric
whose own inputs shift across decades) carries real judgment calls that the
skill-position pool's `transform.py` never had to make. Whether that cost is
worth paying for seven of fourteen roster slots is exactly the scoping
decision `sabotage_draft.md` is waiting on — this document just makes sure
that decision is made against what PFR actually publishes, not an assumption
about it.
