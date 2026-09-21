# QB Season Builder season model

The offline fit behind QB Season Builder's season generation (issue #76, sub-issue
of #72). It takes the finished ratings (the six values per quarterback-season, from
[`../qb_ratings/`](../qb_ratings/)) and the real 2006-2025 results and turns them
into data the game reads: the formulas from six picked values to a stat line and
expected wins, the real spread of noise around them, the playoff ladder, the award
thresholds, the score distributions and the real seasons for the closest-season
comparison. Game rules in
[`docs/games/qb_season_builder.md`](../../docs/games/qb_season_builder.md).

## Loading it

```sh
npm --prefix webapp run db:reset
```

Nothing to run by hand. Migration `0125` creates the tables in
`qb_season_builder_private` (unreachable by any client role) and `0126` fills them.

## What it fits

Everything is per **full season of 17 games**: counting stats and wins are scaled
by the team's games played (so a quarterback who missed time still shows it), and
rates are not. That makes a 16-game 2007 and a 17-game 2023 comparable.

| | |
| --- | --- |
| **Formulas** | Eight outputs, each linear in the six values on a link scale: `attempts`, `comp_pct`, `ypa`, `td_rate`, `int_rate`, `rush_yards`, `rush_td`, `wins`. Yards, touchdowns, interceptions and rating are derived from them, so a generated line agrees with itself. |
| **Extrapolation** | The formulas are fitted, not looked up, so six values above anything real give a season above anything real. The links stop a rate leaving what a game allows (`logit` for completion % and wins, `log` for touchdown and interception rates), and each output has bounds beyond every real season. |
| **Residuals** | For each output, the real residual as a table of quantiles (p = 0 to 1 by 0.05). Noise is drawn by interpolating it, so it is bounded by what really happened. Each output has a `noise_scale`: 1 for `wins` (the team outcome), 0.5 for the quarterback's own line (`LINE_NOISE`; the real season lands in the generated middle 80% of a stat about 45-50% of the time at 0.5, against 30% at 0.3 and 75% at 1.0). |
| **Playoff ladder** | Five rungs (make the playoffs, reach the divisional round, the conference game, the Super Bowl, win it), each the chance of clearing it given the last as a logistic in wins, fitted on every team-season. More wins is never a worse chance, so a slope the data gives the wrong sign is held flat (the Super Bowl rung is a coin flip). |
| **Awards** | MVP, Offensive Player of the Year, First-Team All-Pro, Pro Bowl and Super Bowl MVP. Each has a score (a weighted sum of z-scored stat-line and record metrics) and a threshold at a configured quantile of the **real winners'** scores. Awards nest as they did (`AWARD_REQUIRES`): an MVP must also be All-Pro, and an All-Pro or Offensive Player of the Year a Pro Bowler, or 46% of generated MVPs were not All-Pro against 6% of real ones. Real winners' `spread` is recorded so noise near the edge scales with it. |
| **Score** | How the real seasons spread on stat line, team success and awards, as quantile tables. A generated season is ranked on each as the share of real seasons it is strictly better than (a tie is not better, so a season with no awards, like most real ones, gets nothing on that component); the score is the weighted mix (50 / 30 / 20). A season better than every real one reads 100 on that component. |
| **Real seasons** | Every real quarterback-season on the six values with its real line, record, playoff depth and awards, for the closest-real-season comparison. |

How season generation (issue #77) uses each table is written at the top of
[`0125`](../../supabase/migrations/20260920132000_0125_qb_season_builder_season_model_schema.sql).

### Tuning

All of it is in [`config.py`](./config.py); nothing tunable is a constant in
[`transform.py`](./transform.py) (its only fixed numbers are numerical guards, like
a Newton iteration limit). That includes each output's link and bounds, the noise scales, the
score weights, what each award is judged on, and where each threshold sits among
the real winners. Retune by editing it and generating a new migration.

Three choices are worth knowing about:

- **`attempts` is linear, not log.** A multiplicative link doubled the volume of a
  build that is elite in every trait: all 99 gave 794 attempts and 6,663 yards, a
  record by 20%. Linear gives 5,754 yards and 53 touchdowns, a record by a margin a
  fan could believe.
- **Rushing is a fifth of the stat line (and its touchdowns a tenth).** At a tenth, with
  no touchdowns, Mobility moved a season's score by 10 points from 25 to 99 while IQ
  moved it 34. Now the six values move it by, in order, IQ 32, Accuracy 27, Supporting
  Cast 27, Mobility 19, Build 13 and Arm Talent 7. Arm Talent stays small on purpose:
  given Accuracy and IQ the 20 seasons give it the least of any value, and weighting
  the score to hide that would be an effect the data do not show. Ridge on the line
  formulas was tried to share credit and rejected: it shrinks the quarterback values,
  hands the credit to the (unpenalised) Supporting Cast, and costs fit.
- **The six values do not see scheme.** They explain about half of a quarterback's
  yards, so a fitted season is a regression to the mean, not a replay: Brees's
  5,476-yard 2011 is fitted at about 4,200, and Jackson's 1,206 rushing yards at
  about 465 (still 2.5x the league average). Realism comes from the noise, not from
  the formula chasing outliers.

## Rebuilding it

You do not need to. The seasons are frozen history and the artifact is checked
in. Rebuild to retune, after a ratings retune (the fit is of exactly the values a
player is dealt), or to extend the range with a completed season:

```sh
# a look at the fit and the known quarterbacks first; writes nothing
python3 scripts/qb_season_model/build_model.py --sample

# then a new migration
python3 scripts/qb_season_model/build_model.py \
  --out supabase/migrations/<timestamp>_00xx_qb_season_builder_season_model_retune.sql
```

**Never regenerate an applied migration.** History is append-only, so a retune is
a new file. Every generated file replaces all nine tables outright, so the newest
one is the whole truth.

Inputs, all under `.cache/` (gitignored) unless noted, fetched on the first run
(the ratings pipeline's own cache is used if it is there):

- the finished ratings: read from the newest ratings data migration under
  `supabase/migrations/` (`--ratings` to choose one). Reading the artifact and not
  re-running the ratings pipeline means the fit is of what a player is dealt and
  needs no Madden snapshot.
- nflverse `stats_player_week_{2006..2025}.csv` and `players.csv`: each
  quarterback's real line (touchdowns, rushing) and his Pro Football Reference id.
- nflverse `games.csv`: every team's record and how far it went in the playoffs.
- [`awards.csv`](./awards.csv), checked in: the real quarterback award winners.

Python 3, standard library only. The application never imports any of this.

### `awards.csv`

`season,award,player_id,name`: first-team All-Pro (AP), Pro Bowl, MVP, Offensive
Player of the Year and Super Bowl MVP, quarterbacks only, 2006-2025. Compiled from
Wikipedia's pages for each (the AP All-Pro teams, the Pro Bowl rosters, the MVP,
OPOY and Super Bowl MVP lists) and resolved to Pro Football Reference ids against
the rated seasons. Pro Bowl is every quarterback on the roster, replacements
included. To add a season, append its rows by hand.

Two winners have no row because they have no rated season (fewer than about 150
attempts, so they are not a quarterback-season the game deals): Nick Foles's 2017
Super Bowl MVP and Tyler Huntley's 2022 Pro Bowl. Every row that is here must name a
rated season, or the build stops.

## The guards

The build fails, and writes nothing, on any of these ([`build_model.py`](./build_model.py)):

- an implausible number of quarterback-seasons or team results in a season, a
  rated season with no stat line or team result, or an award naming no rated
  season;
- anything but exactly one First-Team All-Pro quarterback a year, a Pro Bowl of
  fewer than 4 or more than 14, or two MVPs in a year;
- an output whose six values explain less than its floor of the spread
  (`MIN_R_SQUARED`), which is what a broken join looks like;
- **extrapolation not working**: a top-of-scale build whose expected stat line is beaten by
  more than `TOP_BUILD_MAX_BEATEN` (2) real seasons, or does not score in the top
  percentile of the real distribution (a regression fit puts a perfect build's
  *expected* line near the record and lets noise carry it past; with rushing a fifth of
  the stat line, the two seasons above it are Lamar Jackson's), a bottom-of-scale one
  not in the worst decile, a better build that wins no more, or a top-of-scale build with the best of its luck (the top of
  its real spread on wins, and the title) that does not beat every real season on
  team success. Wins cannot pass 17, so a perfect build's *expected* team success
  is not above every real season, but it can be;
- **awards**: one a top-of-scale build does not earn, an average build that earns
  an MVP, Offensive Player of the Year or All-Pro, or a threshold so low that more
  than its bound (`AWARD_SHARE_BOUNDS`) of all real seasons clear it;
- **any known-quarterback expectation** in `EXPECTATIONS`: a quarterback's own six
  values through the fit must land in a band a fan would sign off on (elite passers
  on strong teams, with a better-than-average passer rating; runners who run;
  pocket passers who do not; and the worst of the era who look like it). A failure
  is a clearly wrong fit: fix the formula, not the band;
- a rebuild over shuffled input that is not byte-identical.

## Shape

```
build_model.py    read sources, guards, migration artifact
transform.py      the seam: real seasons + Config -> the fitted model
config.py         links, bounds, noise, weights, thresholds, the known-quarterback checks
awards.csv        the real award winners
test_transform.py test_build_model.py
```

`transform` is the only unit-tested piece of the fit, for the same reason as the
other pools: it is the only piece that can be quietly wrong. Every test passes its
own `Config` and builds its own data from a formula it chose, so retuning the real
numbers cannot break one.

```sh
python3 -m unittest discover scripts/qb_season_model
```
