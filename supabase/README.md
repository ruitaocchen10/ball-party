# Database

Schema, the server-authoritative write API, and its tests. Every game rule that
matters lives here rather than in the client — see
[`docs/architecture/architecture.md`](../docs/architecture/architecture.md).

## Schemas

A game gets a pair of schemas rather than a naming convention, so that `public`
does not become a drawer of `place_bid`, `submit_clue`, `pick_card`. Postgres
schemas are the module boundary the architecture doc describes, and the rule
that a game may not reach into the platform is a `grant` rather than something
a reviewer has to notice.

```
public           platform + contract. Lobbies, runs, matches, post-game.
                 Also the client-readable game tables, since RLS and the
                 Realtime publication are what make them readable.
private          cross-cutting internals, the content module (player_weeks,
                 player_seasons, player_headshots), and — for now — the
                 auction's hidden state (auction_answers, auction_boards).
auction          one game's write API. Exposed through PostgREST.
auction_private  that game's rules engine. Not exposed, and no usage granted
                 to anon or authenticated, so it is unreachable rather than
                 merely unrouted.

higher_or_lower          the same pair for the second game. Its hidden state
higher_or_lower_private  lives in its own private schema rather than in
                         `private` — see 0032.

sabotage_draft           the third game's pair. Its hidden state (a pick's
sabotage_draft_private   identity and season) is a column on a client-readable,
                         Realtime-published table rather than a second
                         physical table — RLS restricts it to the pick's own
                         owner. See 0052 and its test file for why that is
                         still leak-safe.
```

0029 moved functions only. The auction's tables are still split across `public`
and `private`, which is why `auction_private.resolve` writes to
`private.auction_answers`. Moving them touches the Realtime publication and the
policies the 0010 leak test asserts on, so it is worth doing on its own.

Adding a game means adding its two schemas and listing the public one in
`[api] schemas` in `config.toml` — **and in the hosted project's exposed-schema
setting, which is dashboard state that no migration can carry.** A client
reaches it with `supabase.schema("auction").rpc(...)`.

Note that `supabase db reset` does not re-read `config.toml`. Exposing a new
schema locally takes `supabase stop && supabase start`, and until then every
call to it returns PGRST106.

**Deploying 0032 takes that dashboard step.** Migration 0032 adds
`higher_or_lower` to `[api] schemas` above, which covers local development
only. Before the hosted project can start a Higher or Lower match, add
`higher_or_lower` to Settings → API → Exposed schemas (the "Data API" section,
`db-schema` in the PostgREST config) and save. The migration applies fine
without it, and every call to `higher_or_lower.start` fails with PGRST106 until
it is done.

**Deploying 0051 takes it again.** Migration 0051 adds `sabotage_draft` to
`[api] schemas` above, local development only. Before the hosted project can
start a sabotage draft match, add `sabotage_draft` to Settings → API →
Exposed schemas the same way, and save. Until that step, `sabotage_draft.start`
and every other call into the schema fails with PGRST106.

## Migrations

The list below stops at 0011 and has not been kept up; `ls migrations/` is the
authority.

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
npm --prefix webapp run db:reset
```

Ports are moved off the defaults in `config.toml` so this stack can run
alongside another project's. `seed.sql` is local-only and exists to reproduce
the hosted project's default table grants, which a local CLI stack no longer
sets — without it the app hits "permission denied" locally for tables that work
in production. The reset command also restores NFL logos to local Storage.
SQL seed files cannot upload bucket objects, so use this command rather than
calling `supabase db reset` directly when the UI needs logo assets.

### Email confirmation locally

`enable_confirmations` under `[auth.email]` is on, matching the hosted
project — signing up locally requires clicking a confirmation link, same as
prod. Local mail never actually sends; it lands in the fake inbox at
`[local_smtp]` (Studio → the inbox link on port 55324, or `supabase start`'s
own printed URL) instead of a real mailbox. Google sign-in is not configured
locally — `components/auth/GoogleButton.tsx` will error if clicked against
the local stack; use email/password to test auth locally instead.

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
