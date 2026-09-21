# QB Season Builder ratings

The offline pipeline behind QB Season Builder's numbers: five quality values
(Accuracy, Arm Talent, Mobility, IQ, Build, each 0-99) for every qualifying
quarterback-season and a Supporting Cast value for every team-season, 2006
through 2025. Game rules in
[`docs/games/qb_season_builder.md`](../../docs/games/qb_season_builder.md); the
recipe and weights are from issue #72, and the Madden license decision that
allows the talent layer is in
[`docs/games/qb_season_builder_madden_data.md`](../../docs/games/qb_season_builder_madden_data.md).

## Loading it

```sh
npm --prefix webapp run db:reset
```

Nothing to run by hand. Migration `0123` creates the private source table and the
overrides table; `0124` fills them and the finished-values tables that `0120`
created. A fresh clone reaches a playable database in one reset.

## How a value is made

For each trait, two inputs, each ranked **within its season** so they share a
scale, then blended by that trait's weights:

| | Madden (talent) | Stats (that season) |
| --- | --- | --- |
| Accuracy | short / mid / deep accuracy | completion %, CPOE |
| Arm Talent | throw power, deep accuracy | air yards per attempt, 20+ yard completion rate |
| Mobility | speed, acceleration, agility | yards per carry, rushing EPA per game |
| IQ | awareness, play action, throw on the run | passing EPA per dropback (heavy), sack, interception and fumble rates (light) |
| Build | strength, toughness, injury, stamina | height, weight, games played share |

Each input is a weighted mean of its components' within-season ranks, ranked
again; the two ranks are blended by `WEIGHTS` and mapped onto `[value_floor,
value_ceiling]`. The Supporting Cast is the same idea over rostered players:
per slot, the top-N players' Madden overall and their Approximate Value are
ranked across the league that season, combined into an offense half (WR, TE, RB,
OL) and a defense half (DL, LB, CB, S), each half blended by the cast weights,
then offense 70% / defense 30%.

Small samples are pulled toward the league rate (`shrinkage`), because a
150-attempt season is noisy. All of it is in [`config.py`](./config.py); nothing
in [`transform.py`](./transform.py) is a constant.

The edition released *after* a season rates it (edition file `S+1`), falling back
to the pre-season edition (`S`), decided **per trait**: a later edition that
lists a player but not the attribute a trait needs falls back for that trait
only. A quarterback with no usable Madden input for a trait is 100% the stat
side for that trait. Imputed ratings in the source dataset are never used.

### Where this differs from the spec, and why

- **Stat proxies are limited to the weekly file.** The weekly file carries
  CPOE, air yards, EPA, sacks and completions of 20+ yards for the whole
  2006-2025 range (better than the 2010 the issue assumed), but not third-down
  EPA, scrambles or an adjusted completion percentage, and ESPN's QBR is not in
  the feed. IQ leans mostly on passing EPA per dropback (nflverse's `qb_epa`,
  sacks included), with ball security and sack avoidance as a small share;
  Mobility on rushing efficiency, and deep-ball rate is completions of 20+
  yards per attempt.
- **First-down rate per carry is not a Mobility input.** It rewards quarterback
  sneaks, and the spec never asked for it.
- **The value band is 25-99, not 0-99.** A season's worst rated quarterback maps
  to `value_floor` (25) so a qualifying starter never reads as a zero; the
  schema still allows 0-99, and overrides use the full range.
- **2019 has no AV.** nflverse's roster file stops in September 2019 and the AV
  pool (sabotage draft's too) has no 2019 rows. For that season only, the
  rosters are read off the pre-season Madden edition's team field and the
  Supporting Cast is the Madden side alone. Modern editions fold cornerbacks
  and safeties into one `DB` label, so that season counts them all at CB and has
  no Safety slot. To fix it properly, run the PFR scrape for 2019 (see
  [`../av_roster_pool/pfr_scrape.js`](../av_roster_pool/pfr_scrape.js)) and save
  it as `../av_roster_pool/.cache/pfr_2019_2019.txt`; the build picks up every
  `pfr_*.txt` there and stops using the fallback.

## Rebuilding it

You do not need to. The seasons are frozen history and the artifact is checked
in. Rebuild to retune, or to extend the range with a completed season:

```sh
# a look at the result and the known quarterbacks first; writes nothing
python3 scripts/qb_ratings/build_ratings.py --sample

# then a new migration
python3 scripts/qb_ratings/build_ratings.py \
  --out supabase/migrations/<timestamp>_00xx_qb_season_builder_ratings_retune.sql
```

**Never regenerate an applied migration.** History is append-only, so a retune
is a new file. Every generated file replaces `qb_seasons`, `team_seasons`,
`madden_ratings` and `rating_overrides` outright, so the newest one is the whole
truth.

Inputs, all under `.cache/` (gitignored) unless noted:

- `stats_player_week_{2006..2025}.csv` and `players.csv`: nflverse, fetched on
  the first run.
- `madden/{2006..2025}.csv`: a local snapshot of one CSV per edition, the
  dataset's `data/madden/processed/` at the commit pinned in the license doc.
  **Never fetched by this script and never committed**; pass `--madden-dir`
  to point elsewhere.
- `../av_roster_pool/.cache/`: the AV pool's `rosters.csv` and PFR scrape caches,
  for who was on which roster and what each was worth.

Python 3, standard library only. The application never imports any of this.

## The guards

The build fails, and writes nothing, on any of these ([`build_ratings.py`](./build_ratings.py)):

- a season with an implausible number of qualifying quarterbacks or team-seasons,
  a duplicate key, a quarterback with no Supporting Cast row (the schema's
  foreign key), or a value outside 0-99;
- a trait that stops separating quarterbacks within a season;
- Madden coverage collapsing: under 90% of quarterback-seasons or 85% of counted
  roster spots with a rating means the id join has broken and the 70% weights
  are silently doing nothing (real: 96.4% and 92.5%);
- **any known-quarterback expectation** in `EXPECTATIONS`: bands for players a
  fan has an opinion about (a mobile quarterback in a pass-first season, an
  accurate but weak-armed one, a famous supporting cast). A failure is a clearly
  wrong blend; fix the formula or add an override, not the band;
- a rebuild over shuffled input that is not byte-identical.

## Hand overrides

[`overrides.csv`](./overrides.csv) (`franchise_code,season,player_id,slot,value,reason`;
`player_id` empty for `supporting_cast`). The transform applies it, so the guards
see finished values, and the migration loads it into
`qb_season_builder_private.rating_overrides`. To correct a database that is
already loaded without a rebuild, insert a row there and call
`qb_season_builder_private.apply_rating_overrides()` in a migration, then add
the same row to the CSV so a later rebuild keeps it. An override that matches no
row is an error in both places.

## The no-go switch

```sh
python3 scripts/qb_ratings/build_ratings.py --stat-only --out ...
```

Madden weight 0 for every slot and no Madden rows loaded (`STAT_ONLY` in
`config.py`). It needs the 2019 PFR scrape above, because 2019's rosters would
otherwise come from Madden. Measured against the known quarterbacks it fails
one check, Kyler Murray 2021 Mobility (72, band 75-99), which is what the
overrides table is for. Nothing in the schema or the game API changes.

## Shape

```
build_ratings.py  read caches, guards, migration artifact
transform.py      the seam: source rows + Config -> finished values
config.py         weights, bands, slot lists, the known-quarterback checks
test_transform.py
overrides.csv
```

`transform` is the only unit-tested piece, for the same reason as the other
pools: it is the only piece that can be quietly wrong. Every test passes its own
`Config`, so retuning the real numbers cannot break one.

```sh
python3 -m unittest discover scripts/qb_ratings
```

## Licensing

The Madden layer is an accepted-risk go, not a licensed use. The generated
`0124` migration carries third-party ratings and **must never reach a public
repository**; see the conditions in the license doc. The other inputs share the
"licensing is unreviewed" posture of [`../player_pool/`](../player_pool/) and
[`../av_roster_pool/`](../av_roster_pool/).
