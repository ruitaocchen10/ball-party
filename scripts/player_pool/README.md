# Player pool

The auction's lot pool: every NFL player-week from 2010 through 2025, tiered so
a board can be dealt to a quota. Game rules in
[`docs/games/auction_team_builder.md`](../../docs/games/auction_team_builder.md).

## Loading it

```sh
supabase db push
```

That is the whole setup. The table and its rows both arrive as migrations
(`0007` creates it, `0008` fills it), so a fresh clone reaches a loaded database
in one command with no database password and no separate load step.

## Rebuilding it

You do not need to. The seasons are frozen history and the artifact is checked
in. Rebuild only when extending the era range:

```sh
# a newly completed season, as its own migration
python3 scripts/player_pool/build_pool.py --from 2026 --to 2026 \
  --out supabase/migrations/<timestamp>_0009_player_weeks_2026.sql
```

The same migration must rebuild `private.player_seasons` after inserting the
new weekly rows:

```sql
truncate private.player_seasons;
insert into private.player_seasons
  (player_id, season, display_name, position, team, points, pos_rank, tier)
select player_id, season, min(display_name), min(position),
       (array_agg(team order by week desc, team))[1], sum(points)::numeric(5,1),
       min(pos_rank), min(tier)
from private.player_weeks
group by player_id, season;
```

Weekly mode reads `private.player_weeks`; season-total mode reads this SQL-derived
player-season pool. Keeping both current is required before a future season can
be dealt in either scoring mode.

**Never regenerate an applied migration.** Migration history is append-only, so
a new season is a new file. Rebuilds are byte-identical given the same range, so
a diff in a regenerated file means an input changed, not that the build is
noisy.

Python 3, standard library only. The application never imports any of this.

## Tuning the tier bands

`DEFAULT_BANDS` at the top of `build_pool.py` decides which positional finishes
count as star, solid and deep. Tune them by dealing sample boards and reading
the names, not by argument — tier is never shown to players, so it only shapes
the mix.

```sh
python3 scripts/player_pool/build_pool.py --sample --boards 5 --seed 42
python3 scripts/player_pool/build_pool.py --sample --rank-by per_game
```

`--sample` writes nothing and touches no database. It is a preview of pool
composition, not the real dealer — lot scheduling belongs to the auction.

### Where the committed values landed

The starting bands survived their tuning pass. Two readings backed keeping them:

Every band edge is a name you would recognise. In 2023, QB deep runs Geno Smith
to Will Levis and WR deep runs Terry McLaurin to Michael Wilson — the deep tier
is a real starter having a quiet year, not an unguessable practice-squad body.
That matters for a game whose whole skill is recall.

And the tiers separate on points, which is what gives prices something to spread
across. Mean PPR by tier, over all 16 seasons:

|    | star | solid | deep | deep p90 | deep ≤ 0 |
| -- | ---- | ----- | ---- | -------- | -------- |
| QB | 21.6 | 16.9  | 13.4 | 23.1     | 2%       |
| RB | 20.4 | 14.1  | 9.5  | 19.1     | 2%       |
| WR | 19.9 | 14.5  | 10.4 | 20.3     | 4%       |
| TE | 14.4 | 10.0  | 7.0  | 14.5     | 7%       |

A star is worth roughly twice a deep cut on average, so the ladder is real — but
the deep p90 column says a deep cut still spikes into star territory one week in
ten, so paying up is never safe and sitting out is never safe either.

One thing to know: tiering removes most of the duds. 16% of *all* skill weeks
score at or below zero, but only 2–7% of tiered ones do, because a player good
enough to be tiered is a player who mostly plays. The possibility of a zero is
preserved, which is what user story 6 asks for; it is just rarer than the raw
data suggests.

## Shape

```
build_pool.py    fetch, guards, artifact, sampler, and the band configuration
transform.py     the seam: source rows + bands -> finished player-weeks
test_transform.py
```

`transform` is the only unit-tested piece, because it is the only piece that can
be quietly wrong — filters, period-correct team codes, aggregation, ranking,
banding. Fetching and file writing either work or crash loudly.

```sh
python3 -m unittest discover scripts/player_pool
```

The build's own **guards** cover what unit tests cannot see: they run over the
real output and fail the build rather than warn, catching corruption and
coverage — an empty position/tier cell, a duplicate key, a modern team code
surviving before its cutoff, a season count outside what the bands admit, and a
transform that disagrees with itself across two runs.

## Notes

**Why `private`.** The points must be unreadable by the client until the reveal.
PostgREST only exposes configured schemas, so `private.player_weeks` has no REST
endpoint at all — an absence of endpoint rather than a policy that could later
be widened. The auction reads it from inside a `security definer` function and
copies only the card-visible columns onto its lot rows.

**Why `insert` and not `copy`.** `copy ... from stdin` would be the compact
choice, and the design called for it. It does not work: the Supabase CLI applies
migrations over the extended query protocol, and inline copy data desynchronises
that connection — `db push` dies mid-file with SQLSTATE 08P01. Batched multi-row
`insert` costs about 40% more bytes than the equivalent TSV, not the 5x that a
statement-per-row would, so the objection that picked `copy` mostly evaporates.

**Source.** nflverse-data, release tag `stats_player`, one CSV per season. No
API key. Seven columns are used out of roughly 145; nothing else is stored.
Downloads are cached in `.cache/` (gitignored) so re-runs do not re-fetch.

**Licensing is unreviewed.** nflverse is public data, but the terms want reading
before this is in front of anyone outside a playtest.
