# Game runtime

**The contract** between a client and a match: how to get from "no lobby" to a
finished match, how timers and hidden state work, and how a screen stays
correct. Per-RPC signatures are not written here, because they go stale. The
source of truth is the latest migration that defines each function (earlier
migrations are sometimes replaced two or three times), the generated types in
`webapp/lib/supabase/database.types.ts`, and the web and iOS clients.

## Reading an error

Every RPC raises with `raise exception '<message>' using errcode '<code>'`. A
client matches on the **message string**, never the SQL code (see
`CALL_MESSAGES` in `HigherOrLowerMatch.tsx`). The codes are a loose convention:

| Code | Means |
| --- | --- |
| `42501` | Not authenticated, not authorized, or not a member of the thing |
| `P0001` | A domain rule failed (wrong phase, lobby full, wrong game, ...) |
| `P0002` | The referenced row doesn't exist |
| `22023` | The input itself is malformed |
| `55000` | The target isn't in the state the call requires (a locked post) |

Rules that hold for every RPC: `security definer`, identity from `auth.uid()`
and never from an argument, membership checked server-side, and every game rule
enforced in the database (see `architecture.md`).

## Getting into a match

The lobby RPCs live in `public`, owned by the lobbies module (see
[`lobbies/lobbies.md`](./lobbies/lobbies.md)).

- `create_lobby()` hosts a room (a 5-character code from a mishear-resistant
  alphabet) and leaves any lobby the caller was in. `join_lobby(code)` is
  idempotent and leaves other lobbies. A lobby holds up to 4 active members.
  `leave_lobby(id)` migrates host to the longest-tenured member and closes the
  lobby when nobody remains. `close_lobby(id)` is host-only and abandons any
  active run.
- `select_lobby_game(id, game)` records the host's pick (advisory; it starts
  nothing).
- `set_lobby_game_format(id, format)` is host-only and replaces
  `lobbies.game_format`, the host's settings for the games on offer, so the
  rest of the room can see them before Start. An object keyed by game name, each
  value that game's own settings; the platform never reads it (capped at 4KB,
  object only). The game's own `start` is still what takes the settings the
  match is dealt with.
- `start_run(lobby_id, mode, game)` is host-only and returns a `matches` row in
  `status = 'setup'`. It needs 2-4 active members, accepts only `mode =
  'arcade'` (`mode_not_supported` otherwise; party mode does not exist), and
  refuses if a run is already active. It seats the active members into
  `run_participants` in **random** order, which freezes the turn order.
- `start_solo_run(game)` is the lobby-less pair: one participant, `mode =
  'solo'`, guest-eligible.
- Multiplayer needs a real account. Guests get `account_required` from
  `join_lobby`, `select_lobby_game` and `start_run`, and `start_run` also refuses
  a room containing a guest.
- A closed lobby keeps its members attached so the `closed_at` payload reaches
  them. Realtime evaluates RLS at delivery time, so detaching everyone in the
  same transaction would hide the "room closed" event from all of them. Clients
  read closure from `closed_at`.

The returned match's `id` is what every game RPC and Realtime channel keys off.
The game's own `start` RPC then deals it into `playing`.

## Higher or Lower's write API

`supabase.schema("higher_or_lower").rpc(...)` with `start`, `state`, `call`,
`tick`, `advance`, `season_bounds`. Flow: `start` is called once by any
participant on a `setup` match, and deals the ladder. For a group match it also
opens the clock (`phase = 'board_intro'`, 5s). A solo match's first question is
already open and untimed. `state` is the full re-read that reconciliation calls.
`call` locks a direction. `tick` is both the expiry check and the presence stamp
(see the clock section below). `advance` leaves a solo reveal, since solo has no timer.

Tables are `select`-only from the client (all in `public`, match members only,
named `higher_or_lower_*`, plus `match_players` and `matches`). **Hidden state
uses two mechanisms:**

- `higher_or_lower_cards.points` and `revealed_at` are simply `null` in the row
  until that question reveals. The real value lives only in
  `higher_or_lower_private.answers` (RLS on, no policies, all privileges
  revoked), and no endpoint returns it early.
- `higher_or_lower_calls` is an RLS secret: a call is visible to a viewer only if
  it is their own, they have already called that question, or the card is
  revealed. `higher_or_lower_call_statuses` has no columns beyond its key, so its
  existence lets the UI show a "locked in" dot per seat without revealing a
  direction.

A server-written miss (deadline passed with no call) has `direction = null`,
`timed_out = true`, and scores as wrong. `higher_or_lower_player_stats.all_time_high`
is bumped by a trigger as a solo streak grows, so "did this run beat my best?"
must be compared against the row read **before** the first call.

## Huddle's write API

Huddle (the `prompts` schema) has no lobby, run or match: a post is global and
answerable by any signed-in non-guest viewer. None of the lobby RPCs apply. The
write RPCs are `prompts.submit_response`, `post_comment`, `create_post`,
`post_aggregates` and `revealed_responses`, plus `public.my_profile_knower_highlights`
for the profile; read their latest migrations. One hidden-state rule worth
knowing: `private.prompt_slot_answers` has no REST exposure at all (no policy,
every grant revoked), and is reachable only through `resolve_post` on the server.

## The timer/reconciliation state machine (`useMatchClock`)

Every timer-driven match screen — today, Higher or Lower's group matches —
needs the same four behaviors. `webapp/lib/runtime/game-runtime/useMatchClock.ts`
is where the web app learned this the hard way (see its own header comment
for the incident that produced it — three lots in one auction game took 81s,
127s, and 271s, one with no player action at all). This section is that
module as a language-agnostic spec: iOS should implement the same four
behaviors, not port the React hook.

### Tuned constants

| Constant | Value | What it governs |
| --- | --- | --- |
| `VISIBLE_SLACK_MS` | 500 ms | How far before the real deadline the visible countdown reaches zero |
| `TICK_MS` | 100 ms | How often the visible countdown updates |
| `RETRY_MS` | 1,000 ms | How often a client re-asks the server to expire a deadline that has already passed |
| `HEARTBEAT_MS` | 3,000 ms | How often a client that wants a heartbeat asks *before* the deadline passes |
| `STALE_MS` | 4,000 ms | How far past a deadline the client has to be before it stops trusting itself and reconciles |
| jitter | 300–800 ms (`300 + random() * 500`), re-rolled per deadline | Spreads several idle clients' retry asks across a window instead of one stampeded instant |

### 1. The countdown

The client doesn't trust its own clock. It measures `offset = serverTime -
localTime` once per fresh `server_now` value (every RPC response and every
board-row Realtime payload carries one), and derives `now = localTime +
offset` from then on. `remainingMs = max(0, deadline - visibleSlackMs - now)`.
`visibleSlackMs` is the *caller's* choice, not a global: a phase nobody can
act in (a reveal, an intro) passes 0; a phase a move can be sent in passes
`VISIBLE_SLACK_MS`, so a move sent as the visible bar hits zero still lands
inside the real deadline against network latency.

The offset is re-measured only when a fresh `server_now` arrives, never
recomputed on every tick — recomputing it against a stale `server_now` on
every render would snap the countdown to whatever that timestamp said "now"
was at capture, discarding however much real time had actually elapsed since.

### 2. Expiry, asked for repeatedly

A client that calls the expiry RPC exactly once and then latches is the bug
that produced the 81s/127s/271s incident: one no-op — a clock a millisecond
fast, one dropped request — and nobody asks again until a separate janitor
process eventually sweeps the match. Instead: once the deadline (plus that
match's jitter roll) has passed, ask again every `RETRY_MS`, indefinitely,
for as long as the deadline stays past. Being wrong costs nothing — the
server re-checks under its own lock and no-ops if it disagrees. One client
may be exempted entirely (Higher or Lower doesn't use this, but the auction's
player-on-the-clock is the shape it exists for) — everyone else keeps asking
regardless.

### 3. An optional heartbeat

Off by default: most expiry endpoints learn nothing from being asked before
their deadline passes. Higher or Lower's does — its `tick` RPC stamps the
caller present, and a player who never ticks during a question is latched
`absent` at that question's reveal (see `higher_or_lower_players.absent`
above). So Higher or Lower's client asks on a fixed `HEARTBEAT_MS` cadence
*throughout* the phase, not only once it's expired, comfortably faster than
its 12-second call phase so losing one beat to a dropped request doesn't
falsely mark a present player absent. Whether a given RPC's early asks mean
anything is entirely that RPC's business — the clock only knows how often to
ask, and switches to the faster `RETRY_MS` cadence the instant the deadline
passes, sharing one "last asked" timestamp across both so a heartbeat and a
retry never double up right at the boundary.

### 4. Watchdog reconciliation

Realtime is the fast path, not the only path — a single dropped payload must
never leave a screen permanently wrong. A full state re-read (`state`, above)
fires under three conditions:

- **A deadline stays past too long.** Once `now >= deadline + STALE_MS`, the
  client stops trusting its own expiry attempts and re-reads full state
  instead — well behind `RETRY_MS`, so this only fires once expiry has
  already had several unanswered tries.
- **The app returns to the foreground.** Unconditional, regardless of whether
  anything is currently timed — background throttling means the countdown
  above may have barely run while backgrounded, so a foregrounded screen is
  always worth reconciling.
- **The Realtime channel (re)subscribes.** This is the one condition only the
  channel subscription itself can know about — including a plain first
  connect, not only a reconnect. See `realtime.md`'s subscription lifecycle
  section: every channel calls the same reconcile function the instant its
  subscribe callback reports success.

### Pausing

A paused match (`matches.status = 'paused'`) freezes `remainingMs` at
whatever it last read rather than continuing to count down or sitting at
zero, and the client stops asking the server to expire or reconcile anything
until unpaused. The server independently rejects expiry/actions against a
paused match on its own — freezing client-side is the client not bothering to
ask, not the thing that makes pausing safe.

### What doesn't apply to solo

A solo Higher or Lower match never carries a `phase_deadline` (always `null`
after `0084`) — there is nothing to count down, expire, or heartbeat. The
player taps `advance` (above) to leave a reveal instead of a timer pushing
them out. The watchdog's foreground-reconcile condition still applies
unconditionally either way.
