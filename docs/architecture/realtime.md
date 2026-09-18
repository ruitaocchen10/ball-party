# Realtime

Subscription lifecycle, presence, reconnect and mid-match rejoin, connection
state in the UI — see [`architecture.md`](./architecture.md)'s module table.
This doc records the actual, current shape of that contract as implemented in
`webapp/`, not an idealized one: where the web app hasn't built something
(a connection-state indicator, explicit reconnect handling), that's said
plainly rather than invented, so iOS isn't asked to reverse-engineer a richer
contract than what exists.

The mechanism throughout is one thing: a Postgres logical-replication feed
(`supabase_realtime` publication) fanned out over a per-topic WebSocket
channel as `postgres_changes` events, scoped by each table's own RLS `select`
policy — the same policy a plain `select` would enforce. There is no separate
Realtime-specific authorization model to learn.

## Authenticating the socket

Before subscribing to anything, get the current session's access token and
pass it to the Realtime client explicitly:

```ts
// webapp/lib/runtime/realtime/client.ts
const { data: { session } } = await supabase.auth.getSession();
await supabase.realtime.setAuth(session?.access_token ?? null);
```

This has to happen **before** `subscribe()`, not after — a subscription is
registered with whatever claims the socket holds at join time, and calling
`subscribe()` from inside an effect wins the race against the client library
eventually applying the token on its own. Skipping this produces a socket
authenticated as the publishable key alone, which Realtime records as `anon`.
Every table streamed here gates `select` on `auth.uid()` through helpers like
`is_lobby_member`/`is_run_member`/`is_match_member`, so an anonymous
subscriber matches zero rows — **nothing errors, the events just never
arrive**, which is the worst shape this particular bug can take. iOS's
Supabase Swift client needs the equivalent: attach the current session's
access token to the Realtime connection before creating any channel.

## The subscription lifecycle every channel shares

One channel per topic (a match id, a lobby id), created fresh per screen, torn
down on unmount. The shape is identical everywhere it's used:

1. Create a channel named for the topic (`` `higher-or-lower:${matchId}` ``,
   `` `lobby:${lobbyId}` ``, ...).
2. Register one `.on("postgres_changes", { event, schema, table, filter },
   handler)` per table of interest — see the per-channel tables below for the
   exact event/filter per table.
3. `.subscribe((status) => { if (status === "SUBSCRIBED") reconcile(); })` —
   call a full state re-read the instant the subscribe callback reports
   success.
4. On teardown, `removeChannel(channel)`.

**This one `SUBSCRIBED` check is the entire reconnect and mid-match-rejoin
contract.** It fires identically on the very first connect and on every
resubscribe the client library performs after a dropped connection — there is
no separate "reconnected" signal to distinguish the two, and none is needed:
a full reconcile is correct either way. `supabase-js` retries a dropped
Realtime connection on its own; the app does nothing to drive that retry, it
only reacts to the `SUBSCRIBED` callback firing again once it succeeds.

**There is currently no handling of `CHANNEL_ERROR`, `TIMED_OUT`, or `CLOSED`**
anywhere in this codebase's channel subscriptions — every `.subscribe()`
callback either ignores its status argument or checks only for `SUBSCRIBED`.
This is a real gap, not a design the client is choosing not to show iOS: if
iOS wants a richer response to a channel error (a visible "reconnecting"
state, a forced reconcile on `CHANNEL_ERROR` specifically), that's new
behavior with no prior art here to match, not a contract to replicate.

## The `higher-or-lower:${matchId}` channel

Schema `public` throughout.

| Table | Event | Filter |
| --- | --- | --- |
| `higher_or_lower_matches` | `*` | `match_id=eq.${matchId}` |
| `higher_or_lower_cards` | `*` | `match_id=eq.${matchId}` |
| `higher_or_lower_players` | `*` | `match_id=eq.${matchId}` |
| `higher_or_lower_calls` | `INSERT` | `match_id=eq.${matchId}` |
| `higher_or_lower_call_statuses` | `INSERT` | `match_id=eq.${matchId}` |
| `match_players` | `*` | `match_id=eq.${matchId}` |
| `matches` | `UPDATE` | `id=eq.${matchId}` |

`higher_or_lower_calls` and `higher_or_lower_call_statuses` are `INSERT`-only
by construction — both tables are append-only during a match (a call, once
made, is never edited or withdrawn), so there is never an `UPDATE` or
`DELETE` to miss. Every other game table is `*` because its rows do change in
place (a player's streak, a card's reveal, the board's phase).

Payload-handling notes iOS needs, not obvious from the event/filter table
alone:

- A `higher_or_lower_cards` event carrying a **new** `ordinal` (not one
  already held locally) must be *appended*, not require a matching existing
  row to update — endless solo extends the ladder past its pre-dealt twelve
  by inserting new ordinals rather than ever updating one already sent to the
  client.
- A `higher_or_lower_cards` event whose `revealed_at` is now set should
  trigger a **full re-read**, not just apply the payload. A reveal changes
  which `higher_or_lower_calls` rows RLS newly permits for that question (see
  `game-runtime.md`'s hidden-state section), and Realtime does not emit a new
  event for a row whose *visibility* — not content — just changed. Without an
  extra reconcile here, an opponent's already-made call would never appear
  once the reveal makes it visible.
- The `matches` subscription exists solely to detect `status === "paused"` —
  it is not part of the game's own state and carries no other information
  the screen uses.

No separate channel or table set exists for a solo run — it's the same
channel, same tables, same handlers. The differences are entirely in the data
(`is_solo`, `phase_deadline` always `null`) and in which RPC the client calls
in response (`advance` instead of relying on expiry), not in what it
subscribes to.

## The `lobby:${lobbyId}` channel

Schema `public`.

| Table | Event | Filter |
| --- | --- | --- |
| `lobby_members` | `*` | `lobby_id=eq.${lobbyId}` |
| `lobbies` | `*` | `id=eq.${lobbyId}` |
| `runs` | `*` | `lobby_id=eq.${lobbyId}` |
| `matches` | `*` | *(unfiltered)* |

`matches` is subscribed unfiltered because a match is keyed on its `run_id`,
which the lobby screen doesn't know until a run — and therefore a match —
already exists. RLS already scopes the stream to matches of runs the
subscriber belongs to, so unfiltered here is not unguarded; it only looks
broader than the others because the filter would need information this
screen doesn't have yet.

Unlike the match channel, the lobby channel doesn't apply payloads directly —
every event just triggers a full page refresh (`router.refresh()`). That's a
deliberate difference in cost, not an oversight: a server round trip per lobby
event is cheap and lobby membership changes rarely enough not to matter,
where a server round trip per Higher or Lower move would reintroduce the
latency the whole client-applies-payloads approach exists to avoid. One
`lobbies` payload is handled specially: if `closed_at` is now set, the client
navigates away (clearing a temporary guest's session first) instead of
refreshing a room that no longer exists.

## The `post-game:${matchId}` channel

Schema `public`. One subscription: `post_game_actions`, event `INSERT`,
filter `` match_id=eq.${matchId} ``. Carries the host's post-match "replay or
return to lobby" choice (`choose_post_game`, see `game-runtime.md`) to every
other open tab, so a player who isn't the one who tapped the button still
gets carried to the next match or back to the lobby. Payload:
`{ choice: "replay" | "lobby", next_match_id: string | null }`.

## Presence is a heartbeat RPC, not the Realtime Presence feature

The module table names "presence" as something this doc owns, and it's worth
being explicit: **no channel here uses Supabase's dedicated Presence API**
(`.track()`, `.presenceState()`, the `sync`/`join`/`leave` events). Every
notion of "who's actually here right now" in this codebase is instead a
plain heartbeat RPC renewing a `last_seen_at` column, read back through the
ordinary `postgres_changes` mechanism above like any other state change. Two
separate instances of the same pattern:

**Lobby presence.** `LobbyRealtime` calls `public.heartbeat_lobby(p_lobby_id)`
once immediately, then every 10 seconds on an interval, and again on every
`visibilitychange` to `"visible"` — but only while the tab is actually
visible; a backgrounded tab lets the lease lapse. The RPC stamps the caller's
`lobby_members.last_seen_at`; nothing currently reads that column back into
UI (it exists for host-recovery and janitor sweeps — out of scope here), but
iOS should still renew it on the same cadence to keep those server-side
mechanisms working correctly for a mobile-hosted lobby.

**Match presence (Higher or Lower).** The `tick` RPC (see `game-runtime.md`)
serves double duty: it's both the expiry-check `useMatchClock`'s retry
behavior drives, and — via `heartbeatMs` — the presence stamp for the match
itself. A player who never calls it during a question is latched `absent =
true` at that question's reveal, read back through the ordinary
`higher_or_lower_players` subscription above. There is no separate heartbeat
RPC for matches; it's the same call expiry uses, asked more often.

## Connection state in the UI

There currently is no visible "reconnecting" or "offline" indicator anywhere
in the web client — no component renders off Realtime's own connection
status. The only behavior actually driven by connection state is the silent
one already described: a `SUBSCRIBED` callback triggers a reconcile. Treat
that as the current baseline to at least match; a richer indicator on iOS
would be new product surface without a web precedent to mirror, not a gap in
this doc.

## Huddle/prompts: no Realtime subscription at all

Huddle's client code — the feed, posts, comments, responses — contains zero
`.channel(...)` or `postgres_changes` usage anywhere. What it does instead is
a plain server-side read (`fetchPromptFeed`) re-run on navigation and on
every request; there is no client-side polling interval either. Treat Huddle
as **refetch-on-view**, not subscribe-and-apply: iOS should re-fetch a post
or feed when its screen appears, and has no persistent connection to
maintain for it.

One trap worth flagging explicitly: `prompt_posts`, `prompt_slots`,
`prompt_slot_options`, `prompt_slot_exclusions`, and `prompt_comments` **are**
added to the `supabase_realtime` publication (`0094`) —
so, unlike a table nobody ever wired up, the plumbing to stream these exists
at the database level. Nothing in the web client subscribes to it regardless.
**Publication membership is not the same fact as "this is a live channel" —
don't infer one exists on iOS just because these tables are published.**
`prompt_responses` is the one prompts table deliberately kept *out* of the
publication: it's own-row-RLS (a viewer's own pick), and Realtime replicates
a full row over the wire regardless of what RLS would allow that viewer to
`select` — publishing it would leak every other player's pick over the
WebSocket before `post_aggregates` ever revealed it deliberately.
