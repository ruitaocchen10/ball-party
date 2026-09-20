# QB Season Builder — Madden dataset: license and coverage

Closes [#73](https://github.com/ruitaocchen10/ball-party/issues/73), the
prerequisite in [#72](https://github.com/ruitaocchen10/ball-party/issues/72):
before building the Madden-derived talent layer, confirm the published dataset
is usable. Every claim below was checked against the source that owns it (raw
pages fetched and grepped, the dataset's own source code, and the data files
themselves), not a write-up of them. Where something could not be verified it
says so.

## Decision

**GO. The owner accepted the license risk on 2026-09-20.**

The coverage is workable. The license is not: nothing in the chain grants
permission to use these ratings in a shipped product (§2). This is a business
decision to proceed without a license, not a finding that the use is permitted.
It is not legal advice, and no lawyer has reviewed it.

Conditions the go rests on, so they are not lost:

1. **Private and derived only.** The source ratings live only in the private
   table no client role can read. The app, the result page and the API expose
   only blended values, never a Madden input, name or brand (as #72 already
   requires). The "John Madden" mark is separately licensed to EA and may not
   be used without consent (§2.4), which is a second reason for no branding.
2. **The migration that loads the ratings must never reach a public
   repository.** The repo is private today (checked 2026-09-20). If it is ever
   made public or open-sourced, the Madden-bearing migration and any snapshot
   are redistribution, and the layer must be stripped first.
3. **Reversible by configuration.** If a rights-holder objects or the owner
   changes their mind, set the Madden column of the weights table to 0 (§4),
   delete the private table, and the game continues on the stat-only fallback
   (§5). No downstream ticket changes, because they read weights from
   configuration.
4. **Do not vendor the third-party repository.** The pipeline reads a local
   snapshot (pinned in §1) and never links to, mirrors or re-hosts it.

## 1. The dataset

The issue does not name a dataset, so this evaluates the one I found that
publishes the whole range as downloadable files with per-attribute ratings.
Others exist (for example, nfldraftbuzz.com advertises a browsable database
with spreadsheet exports) but were not evaluated:

| | |
| --- | --- |
| Dataset | [`theedgepredictor/nfl-madden-data`](https://github.com/theedgepredictor/nfl-madden-data) |
| Snapshot checked | commit `7443ba168722fc259857ef192fdf3af9ae7f50c5`, 2026-08-04 |
| Shape | one file per NFL season under `data/madden/{raw,stage,processed,dataset}/`, 2001–2025 |
| Maintainer | one author, 5 stars, not archived |

Its README names the source as "maddenratings.weebly.com" (now redirecting to
`maddenratings.net`) and describes the pipeline as "Automated scraping and data
extraction", and `src/extracts/madden.py` shows how:
it opens the fan site's page `madden-nfl-{season+1}` and downloads the Excel
sheet linked there. So the provenance chain is **EA → a fan site → this
repository**.

Three properties of the files matter for the build:

- **The `season` key is the pre-season edition.** File `S` is the Madden edition
  released in August of season `S` (file 2010 = Madden NFL 11). Checked against
  roster facts, not just the scraper's naming: Peyton Manning is on IND in files
  2010–2011 and DEN in 2012; Alex Smith is SF in 2012 and KC in 2013; Kirk
  Cousins is ATL in file 2024. So the edition released *after* season `S`, which
  #72 wants, is file `S+1`, and the pre-season fallback is file `S`.
- **Two editions share the name "Madden NFL 25"** (the 2013 anniversary edition
  and the 2024 edition). File 2013 is special-cased in the scraper, and file
  2024 is commented "pulled externally due to naming conflict", so the 2024 file
  cannot be rebuilt from the repository's own scripts.
- **`processed/` holds observed ratings; `dataset/` holds imputed ones.** The
  `dataset/` files are filled in by a scikit-learn `IterativeImputer` with a
  Ridge model (`src/modeling/imputer.py`). Example: Mahomes' 2018
  `overallrating` there is 66.85, a model estimate and not a Madden number.
  **This document counts only `processed/` values.**

## 2. License

Plain statement: **no party in the chain grants permission to redistribute
these ratings or to use them in a shipped product.** Layer by layer:

1. **The repository: no license.** GitHub's API reports `license: null` and the
   tree has no LICENSE file. GitHub's own documentation states the consequence:
   "without a license, the default copyright laws apply, meaning that you retain
   all rights to your source code and no one may reproduce, distribute, or
   create derivative works from your work"
   ([Licensing a repository](https://docs.github.com/en/repositories/managing-your-repositorys-settings-and-features/customizing-your-repository/licensing-a-repository)).
   The README has no license or data-ownership section. The author is not the
   originator of the ratings in any case.
2. **The fan site: no terms.** `maddenratings.net` publishes no terms of use,
   copyright notice or license (its footer links only a Privacy Policy). The
   Privacy Policy describes it as "an independent fan-created resource" that "is
   not affiliated with, sponsored by, or endorsed by Electronic Arts Inc., EA
   Sports, the National Football League, or any of their respective teams,
   players, or affiliates"
   ([privacy policy](http://www.maddenratings.net/privacy-policy.html)). It has
   no rights in the ratings to grant. The site does not name its operator.
3. **EA, the originator: rights reserved, no data license.** EA's ratings page
   ([ea.com/games/madden-nfl/ratings](https://www.ea.com/games/madden-nfl/ratings))
   is "© 2026 Electronic Arts Inc.", is described as an "Officially Licensed
   Product of NFL PLAYERS INC. and NFLPA.COM" and of the NFL, and offers no
   download, API or license for the data. EA's
   [User Agreement](https://www.ea.com/legal/user-agreement) (last updated
   2026-05-14) grants a "non-commercial" license to use EA Services and says
   "You may not access, copy, modify or distribute any EA Service, Content or
   Entitlements ... unless expressly authorized by EA or permitted by law" and
   "You may not reverse engineer or attempt to extract or otherwise use source
   code or other data from EA Services, unless expressly authorized by EA or
   permitted by law." It defines Content to include "all audio visual or other
   material appearing on or coming from EA Services". Not resolved here: whether
   these terms bind a third party who never used the EA site, whether ratings
   are protectable as facts or as creative judgments, and whether "permitted by
   law" would cover this use. Those are questions for a lawyer.
4. **The "John Madden" mark.** The same EA page says the mark and name of John
   Madden "are trademarks or other intellectual property of Red Bear, Inc. or
   John Madden, are subject to license to Electronic Arts Inc., and may not be
   otherwise used in whole or in part without the prior written consent of Red
   Bear or John Madden." This is why the product must never display "Madden".

**Why the risk is accepted rather than the answer being "permitted":** the
design keeps the ratings in a private table and shows only blended values, which
avoids public redistribution of EA's numbers. It does not create a license. The
ingestion itself still copies a third party's data.

Same posture the repo already takes elsewhere: `scripts/player_pool/README.md`
and `scripts/av_roster_pool/README.md` flag their nflverse and Pro Football
Reference inputs as "Licensing is unreviewed". This one differs in that the
originator is a commercial publisher with an explicit rights notice, not a
public-data project.

## 3. Coverage of quarterbacks, 2006–2025

**Method.** A quarterback-season qualifies as in #72: at least 150 regular-season
pass attempts for one team, summed from nflverse weekly player stats
([`player_stats`](https://github.com/nflverse/nflverse-data/releases/tag/player_stats)
for 2006–2024, [`stats_player`](https://github.com/nflverse/nflverse-data/releases/tag/stats_player)
for 2025). That gives **778 qualifying QB team-seasons** (a QB who cleared the
cutoff on two teams counts twice). Each is matched by nflverse `player_id`
(carried in the dataset's `processed/` files) to an *observed* `overallrating`
in file `S+1` (the edition after), else file `S` (the pre-season fallback), else
none. Every one of the 28 misses was re-checked by name against both files to
rule out a failed join: all are rows that exist with a blank rating (some under
a full-name variant such as "Cameron Ward" or "Thaddeus Lewis").

Per season, showing which edition the game would draw on:

| Season | Qualifying QBs | Pre-season edition | Edition after | Rated in edition after | Filled by pre-season fallback | No observed rating | Covered |
| --- | --- | --- | --- | --- | --- | --- | --- |
| 2006 | 39 | Madden NFL 07 | Madden NFL 08 (file 2007) | 32 | 7 | 0 | 100% |
| 2007 | 41 | Madden NFL 08 | Madden NFL 09 (file 2008) | 32 | 7 | 2 | 95% |
| 2008 | 36 | Madden NFL 09 | Madden NFL 10 (file 2009) | 2 | 33 | 1 | 97% |
| 2009 | 38 | Madden NFL 10 | Madden NFL 11 (file 2010) | 33 | 0 | 5 | 87% |
| 2010 | 36 | Madden NFL 11 | Madden NFL 12 (file 2011) | 26 | 10 | 0 | 100% |
| 2011 | 37 | Madden NFL 12 | Madden NFL 13 (file 2012) | 34 | 1 | 2 | 95% |
| 2012 | 39 | Madden NFL 13 | Madden NFL 25 (file 2013) | 34 | 4 | 1 | 97% |
| 2013 | 42 | Madden NFL 25 | Madden NFL 15 (file 2014) | 37 | 2 | 3 | 93% |
| 2014 | 38 | Madden NFL 15 | Madden NFL 16 (file 2015) | 34 | 2 | 2 | 95% |
| 2015 | 37 | Madden NFL 16 | Madden NFL 17 (file 2016) | 31 | 6 | 0 | 100% |
| 2016 | 36 | Madden NFL 17 | Madden NFL 18 (file 2017) | 33 | 3 | 0 | 100% |
| 2017 | 40 | Madden NFL 18 | Madden NFL 19 (file 2018) | 36 | 3 | 1 | 98% |
| 2018 | 38 | Madden NFL 19 | Madden NFL 20 (file 2019) | 35 | 3 | 0 | 100% |
| 2019 | 38 | Madden NFL 20 | Madden NFL 21 (file 2020) | 36 | 0 | 2 | 95% |
| 2020 | 37 | Madden NFL 21 | Madden NFL 22 (file 2021) | 29 | 6 | 2 | 95% |
| 2021 | 38 | Madden NFL 22 | Madden NFL 23 (file 2022) | 35 | 2 | 1 | 97% |
| 2022 | 39 | Madden NFL 23 | Madden NFL 24 (file 2023) | 35 | 4 | 0 | 100% |
| 2023 | 43 | Madden NFL 24 | Madden NFL 25 (file 2024) | 39 | 2 | 2 | 95% |
| 2024 | 43 | Madden NFL 25 | Madden NFL 26 (file 2025) | 40 | 2 | 1 | 98% |
| 2025 | 43 | Madden NFL 26 | not in dataset | 0 | 40 | 3 | 93% |
| **Total** | **778** | | | **613** | **137** | **28** | **96.4%** |

Per edition file, so the gaps in the attributes the blend needs are visible
(counts are quarterback rows with a non-blank value):

| File | Edition | QB rows | Overall | Throw power | Awareness | Speed | Accel. | Agility |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| 2006 | Madden NFL 07 | 100 | 83 | 83 | 83 | 83 | 83 | 83 |
| 2007 | Madden NFL 08 | 103 | 75 | 75 | 75 | 75 | 75 | 75 |
| 2008 | Madden NFL 09 | 105 | 76 | 76 | 76 | 76 | 76 | 76 |
| 2009 | Madden NFL 10 | 104 | **4** | **0** | **0** | 4 | 4 | **0** |
| 2010 | Madden NFL 11 | 104 | 78 | 76 | 76 | 76 | 76 | 76 |
| 2011 | Madden NFL 12 | 99 | 73 | 69 | 73 | 73 | 73 | 73 |
| 2012 | Madden NFL 13 | 89 | 82 | 82 | 82 | 82 | 82 | 82 |
| 2013 | Madden NFL 25 | 96 | 76 | 76 | 76 | 76 | **0** | 76 |
| 2014 | Madden NFL 15 | 93 | 84 | 84 | 84 | 84 | 84 | 84 |
| 2015 | Madden NFL 16 | 98 | 77 | 77 | 77 | 77 | 77 | 77 |
| 2016 | Madden NFL 17 | 108 | 89 | 89 | 89 | 89 | 89 | 89 |
| 2017 | Madden NFL 18 | 111 | 84 | 84 | 84 | 84 | 84 | 84 |
| 2018 | Madden NFL 19 | 112 | 85 | 85 | 85 | 85 | 85 | 85 |
| 2019 | Madden NFL 20 | 120 | 80 | 80 | 80 | 80 | 80 | 80 |
| 2020 | Madden NFL 21 | 129 | 93 | 93 | 93 | 93 | 93 | 93 |
| 2021 | Madden NFL 22 | 122 | 54 | 54 | 54 | 54 | 54 | 54 |
| 2022 | Madden NFL 23 | 119 | 84 | 84 | 84 | 84 | 84 | 84 |
| 2023 | Madden NFL 24 | 118 | 88 | 88 | 88 | 88 | 88 | 88 |
| 2024 | Madden NFL 25 | 129 | 86 | 86 | 86 | 86 | 86 | 86 |
| 2025 | Madden NFL 26 | 130 | 101 | 101 | 101 | 101 | 101 | 101 |

"QB rows" counts every quarterback the file lists, including backups who never
qualify, so it is larger than the qualifying counts above.
Trait attributes matter only for the rows that resolve, and there they are
complete except in the cases below.

### What the gaps are

- **Two seasons are near-total fallbacks, not sporadic ones.**
  - **2008**: 33 of 36 QBs resolve to the pre-season edition (Madden NFL 09),
    because the Madden NFL 10 sheet (file 2009) is a stub with only 4 rated QBs
    and no throw attributes.
  - **2025**: 40 of 43 resolve to the pre-season edition (Madden NFL 26),
    because the dataset ends at file 2025 and there is no edition after. The
    fan site lists a Madden NFL 27, so a 2026 file could be added, but the
    dataset does not have one.
  - #72 describes the fallback as covering individual quarterbacks. For these
    two seasons the "edition after" rule effectively does not apply, so their
    Madden inputs are pre-season ratings.
- **28 qualifying seasons have no observed rating in either edition (3.6%).**
  Mostly backups and replacement starters, but not only:
  - 2007: Daunte Culpepper (LV, 185 att), Vinny Testaverde (CAR, 172)
  - 2008: Brett Favre (NYJ, 522)
  - 2009: Kurt Warner (ARI, 514), JaMarcus Russell (LV, 247), Marc Bulger
    (LA, 247), Kyle Boller (LA, 176), Daunte Culpepper (DET, 157)
  - 2011: Tarvaris Jackson (SEA, 450), Donovan McNabb (MIN, 156)
  - 2012–2014: Robert Griffin (WAS, 393 / 456 / 214), Thad Lewis (BUF 2013, 157),
    Matt McGloin (LV 2013, 211), Kyle Orton (BUF 2014, 447)
  - 2017: Jay Cutler (MIA, 429)
  - 2019–2024: Dwayne Haskins (WAS 2019, 2020), Gardner Minshew (JAX 2019, 2020;
    IND 2023; LV 2024), Mike Glennon (NYG 2021), Trevor Siemian (NYJ 2023)
  - 2025: Cam Ward (TEN, 540), Michael Penix Jr. (ATL, 276), Carson Wentz
    (MIN, 169)
- **Attribute holes:** Madden NFL 25 (file 2013) has no acceleration column at
  all, so Mobility for season 2012 can use speed and agility only. Madden NFL 12
  (file 2011) lacks throw power on 4 of its 73 rated QBs. Madden NFL 10 (file
  2009) has essentially no attributes.
- **Not checked:** non-quarterback coverage. The Supporting Cast blend in #72
  also wants Madden inputs for receivers, linemen and defenders. This document
  covers quarterbacks only, as the issue asked. The pipeline ticket must check
  the other positions before relying on them.

## 4. Configuration defaults on go

These are the recorded defaults for the blend weights (Madden / stats), as in
#72, and the only place they are written down until the pipeline ticket adds the
real configuration file:

| Trait | Madden | Stats |
| --- | --- | --- |
| Mobility | 70 | 30 |
| Arm Talent | 70 | 30 |
| Build | 50 | 50 |
| Accuracy | 50 | 50 |
| IQ | 60 | 40 |
| Supporting Cast | 50 | 50 |

**Recommendation for the pipeline ticket (not yet decided by the owner):** for a
quarterback-season with no observed rating (the 28 above), use Madden weight 0
and stats weight 100 for that row, with the hand overrides table covering any
that come out clearly wrong. Do not fill those rows from the dataset's imputed
`dataset/` files: they are model estimates on top of an undocumented scrape and
would hide the gap. The same per-row rule would apply to a single missing
attribute (for example acceleration in file 2013).

## 5. Stat-only fallback (the switch if the go is reversed)

If the Madden column goes to 0 for every trait:

- Each of the six values becomes 100% the within-season rank of the stat
  formulas already specified in #72 (completion percentage over expected for
  Accuracy, air yards and deep-ball rate for Arm Talent, and so on). No schema,
  API or game rule changes.
- The weakness is that stats measure usage rather than talent, which is exactly
  why #72 leaned on Madden for Mobility and Arm Talent (70%). Two mitigations,
  both offline: pool a quarterback's rates across all of his seasons to estimate
  the stable talent component before ranking, and use the hand overrides table
  for the known outliers (a rushing quarterback in a low-rushing offense, a
  strong arm in a dink-and-dunk offense). The known-quarterback build-time
  sanity checks stay as the guard.
- Supporting Cast becomes stat-side for both its offensive and defensive halves.

## Sources

- Issue [#73](https://github.com/ruitaocchen10/ball-party/issues/73) and parent
  [#72](https://github.com/ruitaocchen10/ball-party/issues/72)
- [`theedgepredictor/nfl-madden-data`](https://github.com/theedgepredictor/nfl-madden-data)
  at `7443ba1`: README, `madden_runner.py`, `src/extracts/madden.py`,
  `src/modeling/imputer.py`, and `data/madden/{raw,processed,dataset}/`
- GitHub API, `repos/theedgepredictor/nfl-madden-data` (`license: null`)
- [GitHub Docs: Licensing a repository](https://docs.github.com/en/repositories/managing-your-repositorys-settings-and-features/customizing-your-repository/licensing-a-repository)
- [maddenratings.net](http://www.maddenratings.net/) and its
  [privacy policy](http://www.maddenratings.net/privacy-policy.html)
- [EA Madden NFL ratings](https://www.ea.com/games/madden-nfl/ratings) and
  [EA User Agreement](https://www.ea.com/legal/user-agreement), fetched 2026-09-19
- nflverse [`player_stats`](https://github.com/nflverse/nflverse-data/releases/tag/player_stats)
  and [`stats_player`](https://github.com/nflverse/nflverse-data/releases/tag/stats_player)
  releases, for the pass-attempt cutoff
