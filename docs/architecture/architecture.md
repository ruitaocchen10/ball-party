# Architecture

App-wide technical decisions shared by every game in [`games/`](../games/).
Game-specific rules live in their own docs. Session and lobby structure lives in
[`lobbies/`](./lobbies/lobbies.md).

### Shape of the problem

Every game here is a **short-session, small-lobby, turn-based multiplayer game
built on asymmetric information.** That combination is what drives the stack:

- 4 players per lobby, sessions of 5–15 minutes
- Hard per-action timers in every game
- **Hidden state that only some players may see** — the Wavelength target, the
  auction's fantasy points before reveal

### Stack

**Database layer — Supabase.** Postgres for state, Realtime for fanout, RLS for
hidden information, Auth available if wanted.

**Game logic — server-authoritative, in Postgres.** The client calls a function,
the function validates the move and writes, Realtime fans the change out. No
game rule is ever enforced client-side.

Concretely: `security definer` RPCs, the pattern the lobby write API already
uses (`0005`). Edge Functions were the original plan and remain the right home
for logic that has to leave the database — an external API, long-running work —
but nothing here needs that yet, and the auction argues against them. Resolving
a bid is a read-modify-write across five tables that has to be atomic, and a
plpgsql function body is already a transaction. `supabase-js` has no
transaction API, so an Edge Function would either hand-roll BEGIN/COMMIT over a
direct connection or wrap the critical section in an RPC and become a proxy
that added a network hop. That hop is not free when a 10s action timer has to
budget for it.

**One game, one pair of Postgres schemas.** The modules below are a diagram
until something enforces them, and Postgres already has the mechanism: a game
owns `<game>` (its write API, exposed through PostgREST) and `<game>_private`
(its rules engine, unreachable because the schema is). `public` keeps the
platform and the contract. So "a game may never import lobbies" is a `grant`
rather than a convention, deleting a game is `drop schema ... cascade`, and
every game gets to call its function `state` instead of `wavelength_state`. The
auction moved first, in `0029`, and Higher or Lower arrived with the pair
already in place in `0032` — including its hidden state, which the auction
still keeps in `private`. See [`supabase/README.md`](../../supabase/README.md).

**Web UI layer — Next.js deployed in Vercel.** Durable, navigational actions —
create a room, join by code — are server actions ending in a redirect. A move
inside a match is not that shape: it is a client component calling `rpc()`
straight from the browser, keeping Vercel out of the hot path. Safe because the
RPC derives identity from `auth.uid()` and validates the move itself, which is
what made it trustworthy in the first place — never the server action.

## Modules

The split is driven by one question: **what does the platform need to know about
a game in order to host it?** Answer: nothing beyond a contract. Everything else
falls out of that.

```
foundation    identity · content · ui-kit
platform      lobbies → orchestration
runtime       realtime · game-runtime  (the contract)
games         auction · wavelength · higher-or-lower · cah
```

**The rule that keeps this from turning to mush:** a game may depend on the
contract, content, and the UI kit. A game may never import lobbies or
orchestration. If a game needs to know whether it's in a party or an arcade run,
the contract is wrong.

| Module | Doc | Owns |
| --- | --- | --- |
| Identity | `identity.md` *(todo)* | Accounts, profiles, display names, guest vs. authed play |
| Lobbies | [`lobbies/lobbies.md`](./lobbies/lobbies.md) | Room, join code, membership, the lobby→run→match records |
| Orchestration | `orchestration.md` *(todo)* | The party loop: pick next game, launch match, take result, award points, decide the win. Arcade is the degenerate one-match case |
| Game runtime | [`game-runtime.md`](./game-runtime.md) | **The contract.** Match state, action validation, per-action deadlines, hidden-state projection |
| Realtime | [`realtime.md`](./realtime.md) | Subscription lifecycle, presence, reconnect and mid-match rejoin, connection state in the UI |
| Content | [`../../scripts/player_pool/`](../../scripts/player_pool/README.md) | Sports data: players, stats, decks, prompts. Ingestion, caching, freshness, licensing. The auction's player-week pool is built and loaded; decks and prompts are untouched |
| UI kit | `ui-kit.md` *(todo)* | Primitives (`Card`, `Button`) plus the shared **game shell**: timer bar, player rail, reveal |
| Games | [`../games/`](../games/) | Rules for one game, and nothing else. One doc each |

### Notes on the non-obvious ones

**Orchestration is not lobbies.** Lobbies answer *who is here*; orchestration
answers *what happens next*. They're separate because arcade mode needs the
first and almost none of the second.

**Game runtime is the keystone.** Hidden state and server-authoritative rules
both land here, so this is where the design risk concentrates — get the
projection wrong and information leaks through the Realtime payload, not through
the UI. Per-action timers live here too: a deadline the client owns isn't a
rule, so a deadline is a column and expiry is an RPC any participant may call.
The auction settles that shape first — see its pacing section — and the other
timer-driven games should lift it rather than reinvent it.

**Content is the sleeper.** All four games consume sports data and none of them
own it. Untouched so far and likely the longest pole.
