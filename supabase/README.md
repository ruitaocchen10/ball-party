# Database

Schema, the server-authoritative write API, and its tests. Every game rule that
matters lives here rather than in the client — see
[`docs/architecture/architecture.md`](../docs/architecture/architecture.md).

## Migrations

```
0001  profiles                 accounts, and the auth trigger behind them
0002  backfill
0003  lobbies                  lobby / run / match tables, SELECT policies, Realtime
0004  harden definer functions the `private` schema, and why it exists
0005  lobby rpc                the lobby write API
0006  keep members on close
0007  player_weeks             the auction's pool, server-side only
0008  player_weeks 2010-2025   ~40k rows, generated (scripts/player_pool/)
0009  runs and matches         start_run, finish_match, the janitor's hooks
0010  auction board            lots, budgets, the dealer, and the two-table split
0011  auction bidding          bidding, the turn timer, resolution, completion
```

**Migration history is append-only.** An applied file is never edited, not even
for a comment. A change is a new migration.

## Running it locally

```sh
supabase start          # first run pulls images and takes a few minutes
supabase db reset       # apply every migration from scratch, then seed.sql
```

Ports are moved off the defaults in `config.toml` so this stack can run
alongside another project's. `seed.sql` is local-only and exists to reproduce
the hosted project's default table grants, which a local CLI stack no longer
sets — without it the app hits "permission denied" locally for tables that work
in production.

## Tests

pgTAP, installed by `0009`.

```sh
supabase test db
```

Each file runs in a transaction and rolls back, so a suite leaves nothing
behind. Shared fixtures live in `tests/support/harness.psql` and are pulled in
with `\ir`; the `.psql` extension keeps pg_prove from treating them as a test.

The suites act partly as `authenticated` and partly as the owner —
`tests.act_as` switches between them — so RLS is exercised the way a player
experiences it rather than bypassed.

Two of these are worth knowing about:

**The leak test** (`0010`) deals a board and asserts that no client-reachable
relation contains its points, from a participant's session, plus the privilege
and publication facts behind that. It asserts on grants and replication rather
than on what a screen shows, because that is where this particular failure
would be invisible.

**The no-stranding property** (`0011`) plays whole boards out across three table
sizes, three bidding strategies and three seeds, and asserts every player fills
every slot. Eligibility fails by producing a game that runs to completion and is
quietly unfair, which no assertion about a single move would catch.

The pool build has its own tests, in Python:

```sh
python3 -m unittest discover scripts/player_pool
```
