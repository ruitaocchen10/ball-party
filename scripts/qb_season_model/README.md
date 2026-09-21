# QB Season Builder season model

The offline fit behind QB Season Builder's season generation (issue #76, sub-issue
of #72). It takes the finished ratings (the six values per quarterback-season, from
[`../qb_ratings/`](../qb_ratings/)) and the real 2006-2025 results and turns them
into data the game reads: the formulas from six picked values to a stat line and
expected wins, the real spread of noise around them, the playoff ladder, the award
thresholds and the score distributions. Game rules in
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
| **Extrapolation** | The formulas are fitted, not looked up, so six values above anything real give a season above anything real. The links stop a rate leaving what a game allows (`logit` for completion %, attempts and wins, `log` for touchdown and interception rates), and each output has bounds beyond every real season. |
| **Residuals** | For each output, the real residual as a table of quantiles (p = 0 to 1 by 0.05). Noise is drawn by interpolating it, so it is bounded by what really happened. Each output has a `noise_scale`: 0.8 for `wins` (the team outcome, `TEAM_NOISE`; the real season's wins land in the generated middle 80% 66% of the time, 76% at 1.0, traded for less luck in the score), 0.5 for the quarterback's own line (`LINE_NOISE`; the real season lands in the generated middle 80% of a stat about 45-50% of the time at 0.5, against 30% at 0.3 and 75% at 1.0). |
| **Playoff ladder** | Five rungs (make the playoffs, reach the divisional round, the conference game, the Super Bowl, win it), each the chance of clearing it given the last as a logistic in wins, fitted on every team-season. The first rung is sharper than a logistic can be: 12 or more wins always makes it and 5 or fewer never does (`LADDER_GUARANTEES`; no real team broke either, and the fit refuses a guarantee one did), so a 13-4 team cannot miss the playoffs. More wins is never a worse chance, so a slope the data gives the wrong sign is held flat (the Super Bowl rung is a coin flip). |
| **Awards** | MVP, Offensive Player of the Year, First-Team All-Pro, Pro Bowl and Super Bowl MVP. Each has a score (a weighted sum of z-scored stat-line and record metrics) and a threshold at a configured quantile of the **real winners'** scores. Awards nest as they did (`AWARD_REQUIRES`): an MVP must also be All-Pro, and an All-Pro or Offensive Player of the Year a Pro Bowler, or 46% of generated MVPs were not All-Pro against 6% of real ones. All-Pro is judged on the record as well as the stat line, and with wide noise (see `AWARD_NOISE_SCALE`), so an MVP-calibre season with a merely good stat line and a big record can still get there. Real winners' `spread` is recorded so noise near the edge scales with it. |
| **Score** | How the real seasons spread on stat line, team success and awards, as quantile tables. A generated season is ranked on each as the share of real seasons it is strictly better than (a tie is not better, so a season with no awards, like most real ones, gets nothing on that component); the score is the weighted mix (55 / 30 / 15), held to a soft ceiling (`SCORE_CURVE`: unchanged up to 70, harder above it, 0 and 100 fixed). A season better than every real one reads 100 on that component. |

How season generation (issue #77) uses each table is written at the top of
[`0125`](../../supabase/migrations/20260920132000_0125_qb_season_builder_season_model_schema.sql).

### Tuning

All of it is in [`config.py`](./config.py); nothing tunable is a constant in
[`transform.py`](./transform.py) (its only fixed numbers are numerical guards, like
a Newton iteration limit). That includes each output's link and bounds, the noise scales, the
score weights, what each award is judged on, and where each threshold sits among
the real winners. Retune by editing it and generating a new migration.

A few choices are worth knowing about:

- **`attempts` saturates: logit, capped at 670.** A multiplicative (log) link doubled the
  volume of a build that is elite in every trait: all 99 gave 794 attempts and 6,663 yards, a
  record by 20%. A straight line was better but kept climbing past where the real data go flat
  (real seasons in the top build buckets throw 540-560 passes), so well-drafted runs threw
  680+ passes 4.2% of the time (0.6% of real seasons) and 5,500+ yards 2.5% of the time. The
  capped logit gives 0.0% and 0.15%, keeps a record-level passer reachable and costs nothing
  in fit. The cap is `ATTEMPTS_CAP` in `config.py`, which records the sweep.
- **Rushing is a fifth of the stat line (and its touchdowns a tenth).** At a tenth, with
  no touchdowns, Mobility moved a season's score by 10 points from 25 to 99 while IQ
  moved it 34. Ridge on the line formulas was tried to share credit and rejected: it
  shrinks the quarterback values, hands the credit to the (unpenalised) Supporting Cast,
  and costs fit.
- **The six values are balanced on purpose.** Left to the fit they moved a season's score by,
  from 25 to 99, IQ 32.5, Supporting Cast 28.2, Accuracy 26.0, Mobility 16.1, Build 12.9 and
  Arm Talent 7.3: 4.4 to 1, and Arm Talent a round that hardly mattered. The data do say
  Arm Talent adds little once Accuracy and IQ are known, so this leans against them: Arm Talent
  is held at 2.5x its fitted effect on yards per attempt, touchdown rate and wins, Build at 3x on
  wins and Mobility at 1.25x on rushing (`ARM_TALENT_SHARE`, `BUILD_WINS_SHARE` and
  `MOBILITY_RUSH_SHARE`, each a `trim`: the value is held there and the others refit around it).
  Swings were then IQ 28.0, Supporting Cast 26.0, Accuracy 23.3, Mobility 16.6, Build 16.5 and
  Arm Talent 15.4 (1.82 to 1); with the Supporting Cast's effect on the line (next bullet) they
  are Supporting Cast 32.8, IQ 24.4, Accuracy 22.7, Build 16.4, Mobility 16.4 and Arm Talent
  15.2 (2.16 to 1). The price is fit, and it is the honest one: yards per attempt R2
  0.558 to 0.483, touchdown rate -0.023, rush yards -0.031, wins -0.011. It also changes play:
  a skilled drafter no longer leaves Arm Talent as the slot to dump, and knowing which slot
  matters most is worth less (about 1.9 points over picking the biggest number, against 3.3).
- **The Supporting Cast reaches the stat line, and the record follows it a little.** Fitted, the
  cast barely moved a quarterback's line: from a Cast of 25 to 99 a season changed by -84 passing
  yards and +4 touchdowns (a better team leads and throws less). Its effect on yards per attempt
  and touchdown rate is real (t = 4.8 and 5.5) and small (0.12 yards a pass per standard
  deviation of cast, against 0.58 of noise), so it is held at 1.5x the fit there and its effect on
  attempts, not distinguishable from zero (t = -1.7), at none (`CAST_LINE_SHARE`,
  `CAST_ATTEMPTS_SHARE`): +382 yards and +9 touchdowns from 25 to 99. That is a judgment, 2.4
  standard errors past the regression on yards per attempt, and costs almost no fit (R2 0.483
  to 0.478 and 0.463 to 0.457). The other direction is in the data much less: how well a
  quarterback played beyond what his values predict moves his team's wins by a correlation of
  only +0.06 to +0.13 (1% of the record's noise), so the record was drawn independently of the
  line and a build whose passing came out average could go 12-5. The record's draw is now
  correlated 0.3 with the line's (`WINS_LINE_LINK`, migration `0144`, `wins_link` in the model),
  more than the data say and a knob: the record's own spread and a build's average record are
  untouched, and only which record comes with which line changes. Passer rating and wins for the
  same build go from uncorrelated to +0.27, and a build that averages 7.5 wins makes the playoffs
  12.8% of the time when its line came out average (17.8% before) and 50% when it came out good.
  Awards were retuned to keep their real rates once a big line and a big record came together
  (`AWARD_QUANTILE`; All-Pro is sharp: 0.60 gives 2.9% and 0.65 gives 2.3% against 2.6% real).
- **Difficulty is one setting, and it is not on the floor.** The formulas are fitted on real
  seasons and a player who drafts well stacks values a real quarterback rarely has together, so a
  strong build ran well ahead of the real league (a skilled drafter who respins won MVP 8.0% of the
  time, against 2.3% of real seasons, and scored 90+ in 11.8% of runs). The six values now count
  in full up to 70 and only 0.85 of each point above it (`VALUE_CURVE`, `value_curve` in the model,
  migration `0146`): a 90 plays like an 87, a 99 like a 94. A weak build is no weaker, so a poor
  start is no poorer (the worst drafter 22.8 to 22.4), and the strong builds come down: MVP
  4.9%, 90+ 7.3%, a rating of 100+ 38.7% (47.0), playoffs 72.1% (74.8), a conference final or
  better 24.2% (26.7), the title 5.6% (6.6). One number to move it: 0.9 is gentler (MVP 5.8%,
  90+ 8.8%) and 0.8 harder (3.9%, 6.0%). It leaves the balance between the six values as it was
  (2.17 to 1) and the fit alone, but replaying the real builds no longer gives the real league on
  the strong end (MVP 1.2% and All-Pro 1.3% against 2.3 and 2.6), which is the point.
- **Luck is held down and the top is held in.** A well-drafted build's score moved about 10
  points from seed to seed, mostly through team success and the awards (a Pro Bowl alone is
  worth 15 of the 20 award points), not the stat line. The mix moved from 50 / 30 / 20 to
  55 / 30 / 15 and team noise from 1.0 to 0.8, which takes that to about 8 points. Balancing the
  values lifted every above-average build about 1.5 points, and the share of well-drafted runs
  (a skilled drafter who respins) at 90+ from 14% to 18%; redistributing credit does not undo
  that and tighter award cutoffs cost real rates, so a soft ceiling on the score does (see
  `SCORE_CURVE`), and it gives 11%. Linking the record to the line adds a little luck (the score
  moves about 8.2 points from seed to seed, 47% of the variance, up from 7.9 and 46%) and lifted the
  top back to 12.5-13.7%, so the curve's exponent is 1.6 and the share is 11.8%. Replaying the real
  builds still gives the real league: wins 8.1 (8.1), playoffs 35.0% (35.1%), the title 2.6% (2.7%),
  MVP 2.4% (2.3%), All-Pro 2.5% (2.6%), Pro Bowl 24.0% (23.7%).
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
