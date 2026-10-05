# Realtime

How clients stay in sync with the database: socket auth, the subscription
lifecycle, presence, and what the UI does with connection state. This records
the shape as implemented in `webapp/` (and mirrored in iOS), including what is
not built.

The mechanism is a Postgres logical-replication feed (`supabase_realtime`
publication) fanned out over a per-topic WebSocket channel as `postgres_changes`
events, scoped by each table's own RLS `select` policy. Wavelength's live needle
is the one exception (private Broadcast, below). Which tables each channel
subscribes to is in the channel's client code (`webapp/lib/runtime/realtime/`,
the match components, `LobbyRealtime`); only the non-obvious rules are here.

## Authenticating the socket

Before subscribing, pass the session's access token to the Realtime client
explicitly, and do it **before** `subscribe()`:

```ts
// webapp/lib/runtime/realtime/client.ts
const { data: { session } } = await supabase.auth.getSession();
await supabase.realtime.setAuth(session?.access_token ?? null);
```

A subscription registers with whatever claims the socket holds at join time.
Skipping this produces a socket authenticated as `anon`; every streamed table
gates `select` on `auth.uid()`, so an anonymous subscriber matches zero rows.
**Nothing errors, the events just never arrive.** iOS must attach the session's
access token to the Realtime connection before creating any channel.

## The subscription lifecycle every channel shares

One channel per topic (`` `higher-or-lower:${matchId}` ``, `` `lobby:${lobbyId}` ``,
`post-game:${matchId}`, `wavelength:${matchId}`), created per screen and removed
on teardown. Register one `postgres_changes` handler per table of interest, then:

```ts
.subscribe((status) => { if (status === "SUBSCRIBED") reconcile(); })
```

**This one `SUBSCRIBED` check is the entire reconnect and mid-match-rejoin
contract.** It fires on the first connect and on every resubscribe after a drop,
and a full state re-read is correct either way. `supabase-js` retries dropped
connections itself.

There is no handling of `CHANNEL_ERROR`, `TIMED_OUT` or `CLOSED` anywhere: every
callback checks only for `SUBSCRIBED`. Richer handling would be new behavior.

## Channel rules that aren't obvious

- **Higher or Lower** applies payloads directly (a per-move round trip would
  reintroduce latency). Cards and calls are `INSERT`-only where append-only;
  other tables are `*`. A `higher_or_lower_cards` event with a **new** `ordinal`
  must be appended (endless solo extends the ladder by inserting new ordinals).
  A card event whose `revealed_at` is now set must trigger a **full re-read**:
  a reveal changes which `higher_or_lower_calls` rows RLS newly permits, and
  Realtime emits no event for a row whose *visibility* changed. The `matches`
  subscription exists only to detect `status === "paused"`. A solo run uses the
  same channel and tables; only the data differs (`is_solo`, `phase_deadline`
  always `null`).
- **Lobby** subscribes to `lobby_members`, `lobbies`, `runs` and `matches`.
  `matches` is unfiltered because the lobby doesn't know the `run_id` until a
  match exists; RLS already scopes it to the subscriber's runs. Every event
  triggers a full refresh instead of applying the payload (cheap at lobby event
  rates). A `lobbies` payload with `closed_at` set navigates away instead,
  clearing a temporary guest's session first.
- **Post-game** subscribes to `post_game_actions` `INSERT` for the match and
  carries the host's replay-or-lobby choice (`choose_post_game`):
  `{ choice: "replay" | "lobby", next_match_id }`, so other open tabs follow.
- **Wavelength** also joins a private Broadcast channel `wavelength:${matchId}`
  (`config.private: true`) for the `needle` event `{ round, position }`. The
  active guesser sends at most 10 per second and does not apply their own.
  Private Broadcast, because the needle is cosmetic and ephemeral and should not
  be a database write. `realtime.messages` policies allow `SELECT` for match
  members and `INSERT` only for the current round's guesser while the board is
  in `guess`. It is best-effort: a dropped connection leaves the dial usable and
  `lock_guess` scores only the position passed to it. No target or scoring data
  ever crosses it.

## Presence is a heartbeat RPC, not Realtime Presence

No channel uses Supabase's Presence API (`.track()`, `.presenceState()`).
"Who's here" is a heartbeat RPC renewing a `last_seen_at` column, read back
through ordinary `postgres_changes`:

- **Lobby.** `LobbyRealtime` calls `public.heartbeat_lobby(p_lobby_id)` once, then
  every 10s and on every `visibilitychange` to visible, only while the tab is
  visible. It stamps `lobby_members.last_seen_at`, which host recovery and
  janitor sweeps use; iOS should renew on the same cadence.
- **Higher or Lower.** The `tick` RPC is both the expiry check and the presence
  stamp, driven by `useMatchClock`'s `heartbeatMs`. A player who never ticks
  during a question is latched `absent` at its reveal. There is no separate
  heartbeat RPC.

## Connection state in the UI

There is no visible "reconnecting" or "offline" indicator. The only behavior
driven by connection state is the silent reconcile on `SUBSCRIBED`.

## Huddle: refetch-on-view

Huddle's client code has no `.channel(...)` or `postgres_changes` usage. It does
a server-side read (`fetchPromptFeed`) per navigation or request, with no
polling. Re-fetch a post or feed when its screen appears.

**Publication membership is not the same fact as "this is a live channel."**
`prompt_posts`, `prompt_slots`, `prompt_slot_options`, `prompt_slot_exclusions`
and `prompt_comments` are in the `supabase_realtime` publication (`0094`), but
nothing subscribes. `prompt_responses` is deliberately kept out: it is own-row
RLS, and Realtime replicates the full row regardless of what RLS allows the
viewer to `select`, so publishing it would leak every other player's pick before
`post_aggregates` reveals it.
