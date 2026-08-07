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

**Game logic — TypeScript, in Edge Functions.** The client calls a function, the
function validates the move and writes to Postgres, Realtime fans the change
out. No game rule is ever enforced client-side.

**Web UI layer - Next.js deployed in Vercel**

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
| Game runtime | `game-runtime.md` *(todo)* | **The contract.** Match state, action validation, per-action deadlines, hidden-state projection |
| Realtime | `realtime.md` *(todo)* | Subscription lifecycle, presence, reconnect and mid-match rejoin, connection state in the UI |
| Content | `content.md` *(todo)* | Sports data: players, stats, decks, prompts. Ingestion, caching, freshness, licensing |
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
rule. Worth settling early whether an Edge Function round-trip per action is
fast enough for the timer-driven games, since the answer shapes this module.

**Content is the sleeper.** All four games consume sports data and none of them
own it. Untouched so far and likely the longest pole.
