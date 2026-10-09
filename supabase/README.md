# Database

Schema, the server-authoritative write API, and its tests. Every game rule that
matters lives here rather than in the client — see
[`docs/architecture/architecture.md`](../docs/architecture/architecture.md).

## Schemas

A game gets a pair of schemas rather than a naming convention, so `public` does
not become a drawer of `place_bid`, `submit_clue`, `pick_card`. Postgres schemas
are the module boundary the architecture doc describes, and "a game may not
reach into the platform" is a `grant` rather than something a reviewer has to
notice.

```
public           platform + contract. Lobbies, runs, matches, post-game, and
                 the client-readable game tables (RLS and the Realtime
                 publication are what make them readable).
private          cross-cutting internals and the content pools
                 (player_weeks, player_seasons, player_headshots), plus the
                 auction's hidden state (auction_answers, auction_boards).

<game>           one game's write API, exposed through PostgREST.
<game>_private   that game's rules engine and hidden state. Not exposed, and no
                 usage granted to anon or authenticated, so it is unreachable
                 rather than merely unrouted.
```

Games with a pair: `auction`, `higher_or_lower`, `sabotage_draft`,
`qb_season_builder`, `wavelength`, and `prompts` (the Huddle). A client reaches
one with `supabase.schema("auction").rpc(...)`.

Where a game keeps hidden state differs, and the game's own schema migration
header explains why:

- **auction:** the tables are still split across `public` and `private`
  (`auction_private.resolve` writes `private.auction_answers`). Moving them
  touches the Realtime publication and the policies the `0010` leak test asserts
  on, so it should be done on its own.
- **higher_or_lower, qb_season_builder, wavelength:** hidden state lives only in
  the `_private` schema. For QB Season Builder, hidden mode is enforced by what
  the API returns, so no client-selectable table holds a number.
- **sabotage_draft:** a pick's identity and season are columns on a
  client-readable, Realtime-published table, restricted by RLS to the pick's
  owner (see `0052` and its test for why that is leak-safe).

### Adding a game

Add its two schemas, and list the public one in `[api] schemas` in
`config.toml`. **Also add it to the hosted project's Settings → API → Exposed
schemas, and save. That is dashboard state no migration can carry.** The
migration applies fine without it, and every call into the schema then fails
with `PGRST106` until it is done. Locally, `supabase db reset` does not re-read
`config.toml`; run `supabase stop && supabase start` to expose a new schema.

## Migrations

`ls migrations/` is the list.

**Migration history is append-only.** An applied file is never edited, not even
for a comment. A change is a new migration. (This is why some old migration
comments cite doc paths that have since moved.)

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
locally — `webapp/components/foundation/identity/GoogleButton.tsx` will error if clicked against
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
