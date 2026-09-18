# Game runtime

**The contract.** Everything a client needs to call in order to get from "no
lobby" to "a finished match," for the two verticals the iOS app ships first —
Higher or Lower and Huddle (see issue #59). "Huddle" is this app's name for
the `prompts` schema: a global ball-knowledge prediction and comment feed,
answerable by any signed-in player without a lobby or a match. It doesn't
appear in the games diagram or `docs/games/` above precisely because it isn't
lobby/match-shaped the way `auction · wavelength · higher-or-lower · cah` are
— see its own section below for why none of the lobby/match RPCs apply to it.
Written so iOS can be implemented deliberately from this doc instead of
reverse-engineered from the TypeScript in `webapp/`. The auction, sabotage
draft, and 2v2 wavelength are not covered here yet; their write APIs exist but
are still *(todo)* for this doc.

Every signature below is the current, final one — migration history in
`supabase/migrations/` sometimes replaces a function two or three times, and
only the latest replacement is load-bearing. Where that matters (a shape or a
guard changed), it's called out.

## Reading an error

Every RPC here raises with `raise exception '<message>' using errcode
'<code>'`. The web client matches on the **message string**, never the SQL
error code — see `CALL_MESSAGES` in `HigherOrLowerMatch.tsx` for the pattern
iOS should follow. The codes themselves are a loose, not-machine-critical
convention across this codebase:

| Code | Means |
| --- | --- |
| `42501` | Not authenticated, not authorized, or not a member of the thing |
| `P0001` | A domain rule failed (wrong phase, lobby full, wrong game, ...) |
| `P0002` | The referenced row doesn't exist |
| `22023` | The input itself is malformed (bad shape, bad option id) |
| `55000` | The target isn't in the state the call requires (a locked post) |

## Getting into a match

These RPCs belong to the **lobbies module** (`public` schema), not to
game-runtime — see [`lobbies/lobbies.md`](./lobbies/lobbies.md) and
[`architecture.md`](./architecture.md) for why lobbies and game-runtime are
separate modules. They're documented here anyway because a client needs the
whole path, and nothing else writes down their exact signatures. All are
`security definer`, all derive identity from `auth.uid()`, never from an
argument.

### `public.create_lobby()`

```sql
create_lobby() returns public.lobbies
```

Rejects: no session, or a guest (`is_anonymous` JWT claim) → `not_authenticated`.
Leaves any lobby the caller was already in (`leave_all_lobbies`), generates a
5-character code from a mishear-resistant alphabet (`0`/`O`, `1`/`I`/`L`
excluded), retries on collision up to 10 times (`code_generation_failed`),
inserts the `lobbies` row and seats the caller as its first `lobby_members`
row. Called once, to host a room.

### `public.join_lobby(p_code text)`

```sql
join_lobby(p_code text) returns public.lobbies
```

Rejects: no session → `not_authenticated`; a guest → `account_required` (added
in `0113` — mobile has no guest session at all, so this path is theoretical for
iOS, but the error exists); no open lobby with that code → `lobby_not_found`;
4 other active members already seated → `lobby_full`. Idempotent: rejoining a
room you're already an active member of no-ops and returns the lobby, so a
retried call after a flaky connection is safe. On success, leaves every other
lobby the caller was in, then upserts a `lobby_members` row — a *returning*
player keeps their original `joined_at` rather than being reseated at the
back.

### `public.leave_lobby(p_lobby_id uuid)`

```sql
leave_lobby(p_lobby_id uuid) returns void
```

Rejects: no session → `not_authenticated`; caller has no active membership in
that lobby → `not_a_member` (`P0001`, not `42501` — the one exception to the
"membership failures are `42501`" pattern used elsewhere). On success: marks
the caller's `left_at`, migrates host to the longest-tenured remaining member
if the leaver was host, and closes the lobby entirely if nobody active
remains.

### `public.close_lobby(p_lobby_id uuid)`

```sql
close_lobby(p_lobby_id uuid) returns void
```

Rejects: no session → `not_authenticated`; no open lobby with that id →
`lobby_not_found`; caller isn't `lobbies.host_id` → `not_host`. On success:
sets `closed_at`, marks every active member `left_at`, and marks any active
run for the lobby `'abandoned'`.

### `public.select_lobby_game(p_lobby_id uuid, p_game text)`

```sql
select_lobby_game(p_lobby_id uuid, p_game text) returns void
```

Host-only, pre-start. Rejects: no session → `not_authenticated`; guest →
`account_required`; no open lobby with that id → `lobby_not_found`; lobby
closed → `lobby_closed`; caller isn't host → `not_host`; caller has no active
membership → `not_a_member`. On success: `lobbies.selected_game = p_game`
(e.g. `'higher_or_lower'`). Purely advisory state for the room screen — it
does not start anything by itself.

### `public.start_run(p_lobby_id uuid, p_mode public.run_mode, p_game text)`

```sql
start_run(p_lobby_id uuid, p_mode public.run_mode, p_game text) returns public.matches
```

Host-only. Rejects, in order: no session → `not_authenticated`; guest caller
→ `account_required`; lobby missing → `lobby_not_found`; lobby closed →
`lobby_closed`; caller isn't host → `not_host`; caller not an active member →
`not_a_member`; **any current active member is a guest** → `account_required`
(a `0113` guard against a guest grandfathered into the room before `join_lobby`
started refusing them — closes the gap `join_lobby`'s own guard leaves);
active-member count outside `[2, 4]` → `bad_player_count`; `p_mode` isn't
`'arcade'` → `mode_not_supported` (party mode doesn't exist yet); a run is
already active for this lobby → `run_already_active`. On success: creates a
`runs` row, seats every active `lobby_members` row into `run_participants` in
**random** order (this is the turn-order freeze the two-roster split in
`lobbies.md` describes), and creates a `matches` row (`seq = 1`, `status =
'setup'`). Returns that `matches` row — its `id` is the match id every
subsequent RPC and the Realtime channel key off.

### `public.start_solo_run(p_game text)`

```sql
start_solo_run(p_game text) returns public.matches
```

Not lobby-scoped at all — no lobby, no host check, no roster, and unlike
`start_run` it does **not** refuse a guest (solo remains guest-eligible; only
multiplayer requires a real account). Rejects only: no session →
`not_authenticated`. Creates a `runs` row with `lobby_id = null` and `mode =
'solo'`, a single `run_participants` row (`seat = 0`), and the `matches` row.
Same return shape as `start_run` — the two are the multiplayer/solo pair that
both produce a `matches` row in `'setup'`, which the game's own `start` RPC
then deals into.

## Higher or Lower's write API (`higher_or_lower` schema)

Exposed through PostgREST as `supabase.schema("higher_or_lower").rpc(...)`.
Every RPC here is `security definer` and checks match membership via
`private.is_match_member`/`run_participants`, never trusts an argument for
identity.

### `higher_or_lower.start(p_match_id uuid, p_scoring_mode text default 'season_total', p_season_from smallint default null, p_season_to smallint default null)`

```sql
start(
  p_match_id uuid,
  p_scoring_mode text default 'season_total',
  p_season_from smallint default null,
  p_season_to smallint default null
) returns higher_or_lower.board
```

Called once, by any participant, immediately after `start_run` or
`start_solo_run` returns a `'setup'` match. Rejects: no session →
`not_authenticated`; `p_scoring_mode` not in `('weekly', 'season_total')` →
`invalid_scoring_mode`; an invalid season range for the requested era →
whatever `higher_or_lower_private.resolve_season_range` raises; match id
doesn't exist → `match_not_found`; `matches.game <> 'higher_or_lower'` →
`wrong_game`; caller isn't a participant in the match's run →
`not_a_participant`; match isn't `'setup'` → `match_not_setup`. On success:
deals the ladder (`higher_or_lower_private.deal_board`), sets `matches.status
= 'playing'` and `started_at`, and — **for a group match only** — opens the
clock: `phase = 'board_intro'`, `phase_deadline = now() + 5s`. A solo match's
first question is already open, untimed, from inside `deal_board` itself, so
this step is skipped for it (`is_solo`). Returns the freshly dealt board.

### `higher_or_lower.state(p_match_id uuid)`

```sql
state(p_match_id uuid) returns higher_or_lower.board
```

The full-reread RPC `useMatchClock`'s `reconcile` calls. Rejects only:
caller isn't a match member → `not_a_participant`. Returns the same
`higher_or_lower.board` projection `start` does — deliberately a named
projection, not `select *`, so it can never leak a column that hasn't been
added to it on purpose.

### `higher_or_lower.call(p_match_id uuid, p_direction text)`

```sql
call(p_match_id uuid, p_direction text) returns public.higher_or_lower_calls
```

The move. Rejects: no session → `not_authenticated`; `p_direction` not
`'higher'`/`'lower'` → `invalid_direction`; match not `'playing'` →
`match_not_playing`; caller not a participant → `not_a_participant`; current
phase isn't `'call'`/`'sudden_death_call'` → `call_not_open`; caller isn't
alive in sudden death → `not_alive_in_sudden_death`; the phase deadline has
already passed (group matches only — solo has none) → `call_deadline_passed`;
caller already called this question → `already_called`. Returns the written
call row.

### `higher_or_lower.tick(p_match_id uuid)`

```sql
tick(p_match_id uuid) returns higher_or_lower.board
```

This is the `expire` function `useMatchClock` drives for Higher or Lower — see
[the timer section](#the-timerreconciliation-state-machine-usematchclock)
below. Any match participant may call it, repeatedly; it is free to be wrong.
Internally: locks the match row, unconditionally stamps the caller present
first (`higher_or_lower_players.last_seen_at = now()`, `absent = false`), then
re-checks whether the current phase's deadline has passed and advances the
board if so — the same call doubles as the heartbeat, and presence is stamped
before the expiry check specifically to avoid a lock-ordering conflict with
`call`. A player whose `last_seen_at` predates the
question's open time when it reveals is latched `absent = true`, which is why
every client, not just the one on the clock, has to keep calling this
throughout the question rather than only after the deadline. A no-op on a
match whose current phase has no deadline (a solo match, always).

### `higher_or_lower.advance(p_match_id uuid)`

```sql
advance(p_match_id uuid) returns higher_or_lower.board
```

Solo's replacement for the clock: a solo board never carries a `phase_deadline`
after `0084`, so nothing ever expires it, and the player taps "Continue"
instead. Rejects: no session → `not_authenticated`; match not `'playing'` →
`match_not_playing`; match isn't solo → `not_solo`; caller not a participant
→ `not_a_participant`; current phase isn't `'reveal'` → `advance_not_open`.

### The `higher_or_lower.board` type

Every RPC above that returns board state returns this same shape:

```sql
create type higher_or_lower.board as (
  match_id          uuid,
  question_count    smallint,
  spare_count       smallint,
  current_question  smallint,
  scoring_mode      text,
  season_from       smallint,
  season_to         smallint,
  phase             text,
  phase_deadline    timestamptz,
  server_now        timestamptz
);
```

`phase` is one of `'board_intro' | 'call' | 'reveal' | 'sudden_death_call' |
'sudden_death_reveal' | 'complete'`. `server_now` is `now()` at read time —
feed it straight into the clock's `serverNow` input (below) to measure the
client/server clock offset. `phase_deadline` is `null` whenever nothing is
timed, including for the entire duration of a solo match.

## Higher or Lower's tables (read directly, not through an RPC)

All in `public` schema. Everything below is `select`-only from the client —
no game rule is ever writable except through the RPCs above.

| Table | Key | Columns of interest | Who may `select` |
| --- | --- | --- | --- |
| `higher_or_lower_matches` | `match_id` | `question_count, spare_count, current_question, scoring_mode, season_from, season_to, phase, phase_deadline, is_solo` + sudden-death bookkeeping | Match members only |
| `higher_or_lower_cards` | `match_id, ordinal` | `player_id, display_name, position, season, team, week, opponent, headshot_url, points, revealed_at` | Match members only |
| `higher_or_lower_players` | `match_id, user_id` | `seat, current_streak, best_streak, correct_count, last_seen_at, absent, sudden_death, eliminated_at` | Match members only |
| `higher_or_lower_calls` | `match_id, question, user_id` | `direction, created_at` | See below — not simply "match members" |
| `higher_or_lower_call_statuses` | `match_id, question, user_id` | (existence only) | Match members only |
| `match_players` | `match_id, user_id` | `team, raw_score, placement, points_awarded` | Match members only (platform table, written once by `finish_match` at completion) |
| `matches` | `id` | Client reads `status` specifically to detect `'paused'` | Run members only (platform table) |

**Hidden state has two different mechanisms here, and iOS needs both:**

`higher_or_lower_cards.points`/`revealed_at` are simply `null` in the row
until that ordinal's question reveals — a write-time secret, not an RLS
secret. The real value lives only in `higher_or_lower_private.answers`, a
table with RLS enabled, zero policies, and every privilege revoked from
`anon`/`authenticated`. No endpoint ever returns it before the reveal writes
it into the public row.

`higher_or_lower_calls` is an RLS secret instead: a row is visible to a
viewer only if it's their own call, **or** they have already called that
question themselves, **or** that question's card is already revealed. This is
what keeps an opponent's in-flight call invisible while yours is still open,
without withholding it forever. `higher_or_lower_call_statuses` deliberately
carries no columns beyond its key — its mere existence (visible to *any*
match member regardless of the calls policy) is what lets the UI show a
"locked in" dot for every seat without revealing which way anyone called.

## Huddle's write API (`prompts` schema)

Huddle has **no lobby, no run, no match** — a post is global, answerable by
any signed-in non-guest viewer, not scoped to a session (see `0094`'s header
comment). None of `create_lobby`/`join_lobby`/`start_run`/etc. apply to it at
all. All RPCs below are `security definer`, `schema prompts`, granted to
`authenticated` unless noted.

### `prompts.submit_response(p_post_id uuid, p_choices jsonb, p_comment text default null)`

```sql
submit_response(p_post_id uuid, p_choices jsonb, p_comment text default null) returns void
```

One call answers every slot on a post. `p_choices` shape: `{slot_id:
[option_id, ...]}`; array order matters only for a `rank`-shaped slot.
Rejects: no session or a guest → `not_authenticated`; post missing →
`post_not_found`; post not `'open'` or past `lock_at` → `post_locked`; wrong
option count for the slot's shape (`pick` → exactly 1; `pick_set`/`rank` →
`pick_count`) or a duplicate option id → `incomplete_slot`; an option id that
doesn't belong to that slot → `invalid_option`; a team already spoken for by
another slot via `prompt_slot_exclusions` → `option_already_used`. Writes one
`prompt_responses` row per slot (upserted on `(slot_id, profile_id)`), and, if
`p_comment` is non-empty, a `prompt_comments` row with `posted_with_pick =
true` in the same call.

### `prompts.post_comment(p_post_id uuid, p_body text, p_parent_comment_id uuid default null)`

```sql
post_comment(p_post_id uuid, p_body text, p_parent_comment_id uuid default null) returns uuid
```

Rejects: no session or a guest → `not_authenticated`; post missing →
`post_not_found`; `p_parent_comment_id` given but not found, or belongs to a
different post → `parent_not_found`; the parent is itself a reply (nesting
past one level) → `nested_reply`. Returns the new comment's id. Omit
`p_parent_comment_id` for a top-level take; pass it for a one-level-deep
reply.

### `prompts.create_post(...)`

```sql
create_post(
  p_template_kind       text,   -- 'game_pick' | 'stat_leader' | 'ranking' | 'custom_multi'
  p_template_name       text,
  p_caption             text,
  p_prompt_text         text,
  p_resolution_criteria text,
  p_lock_at             timestamptz,
  p_slots               jsonb,
  p_resolution_source   jsonb default null,
  p_is_opinion          boolean default false
) returns uuid
```

**Admin-only** — checked in the function body against
`prompts_private.admin_config` (matched by JWT email), not at the grant layer;
it's granted to every `authenticated` caller the same way every RPC in this
codebase is, per convention (see `supabase/README.md`). This is the web
admin composer's entry point, not a player action — iOS's v1 scope (issue
#59) has no post-authoring surface, so this almost certainly isn't called
from the app. Documented here for completeness in case that changes.
`p_slots` is an array, one object per slot in display order:
`{label, shape, pick_count, points, source_game_id, excludes_slot_indexes,
options: [{label, sublabel, team_code, headshot_url, sort_order}]}` —
`excludes_slot_indexes` are 0-based indexes into `p_slots`, not ids, since the
slots don't have ids yet at call time.

### `prompts.post_aggregates(p_post_id uuid)`

```sql
post_aggregates(p_post_id uuid)
  returns table (slot_id uuid, option_id uuid, pct numeric, total_responses bigint)
```

**No auth check at all** — granted to `anon`, callable signed out. Per option:
`pct` is the rounded percentage of that slot's responses that chose it (`null`
if the slot has zero responses yet), `total_responses` is the slot's response
count. This is the *only* sanctioned way to see what other players picked —
`prompt_responses` itself is own-row-only (below) and deliberately excluded
from Realtime (see `realtime.md`). Call this for any post that isn't
`'open'`, or that the viewer has already answered.

### `prompts.revealed_responses(p_post_id uuid)`

```sql
revealed_responses(p_post_id uuid)
  returns table (profile_id uuid, slot_id uuid, chosen_option_ids uuid[])
```

Also granted to `anon`, no auth check. Only guard: the post must be past
`lock_at` or `status = 'resolved'`, else `picks_not_revealed`. Returns every
response row for the post, full ticket per profile (not aggregated) — this is
what lets a "take" comment display the poster's full pick alongside their
comment.

### `public.my_profile_knower_highlights()`

```sql
my_profile_knower_highlights()
  returns table (window_key text, total_points integer, percentile integer)
```

Note the schema: `public`, not `prompts`. `security definer`, granted to
`authenticated` only (not `anon`). No parameters — everything is keyed off
`auth.uid()` internally, and there's **no explicit auth-null guard**, so a
caller with no session gets back all-zero/all-null rows rather than a thrown
error. Always returns exactly 4 rows, one per window (`'lifetime' | 'year' |
'month' | 'week'`): the caller's summed `points_earned` across resolved posts
in that window (0 if none), and their percentile among everyone **who hasn't
opted out of rankings visibility** (`profiles.rankings_visible`, `0109`) and
has points in that window (1–100, higher is better; `null` if the caller has
none, or if the caller themself has opted out — their own `total_points`
still accrues either way, only the percentile comparison excludes them).

### Not Huddle RPCs, despite appearing adjacent

**`public.choose_post_game(p_match_id uuid, p_choice public.post_game_choice)`**
is a platform/orchestration RPC (`0023`, extended for replay in `0039`/`0047`/
`0084`) that operates on `matches`/`runs`/`lobbies` — the "replay or return to
lobby" choice after a *match* ends. It has nothing to do with Huddle's
*posts*; the naming overlap ("post-game" vs. "prompt post") is coincidental.
It's the RPC behind Higher or Lower's own post-match screen — document it
once, in an orchestration doc, not under either game.

**`public.claim_guest_identity()`** and
**`public.record_guest_account_collision(p_nonce uuid)`** (`0016`/`0017`) are
a **web-only** pair that reattaches a browser guest session's match history
once that guest later signs up for a real account, in the same browser
session. `0113`'s own header states it plainly: *"iOS never carries a guest
session at all."* There is no guest identity on mobile for either RPC to ever
claim or collide with — skip both entirely.

## Huddle's tables (read directly)

All `public` schema.

| Table | Columns | RLS for `select` |
| --- | --- | --- |
| `prompt_posts` | `id, template_kind, template_name, author_id, caption, prompt_text, resolution_criteria, lock_at, status, void_reason, resolved_at, resolution_source, is_opinion` | `anon, authenticated` — `using (true)` |
| `prompt_slots` | `id, post_id, label, shape, pick_count, points, sort_order, correct_option_ids` | `anon, authenticated` — `using (true)`; `correct_option_ids` is `null` until resolution, same reveal-by-write-not-by-policy trick as `higher_or_lower_cards.points` |
| `prompt_slot_options` | `id, slot_id, label, sublabel, team_code, headshot_url, sort_order` | `anon, authenticated` — `using (true)` |
| `prompt_slot_exclusions` | `slot_id, excluded_slot_id` | `anon, authenticated` — `using (true)` |
| `prompt_comments` | `id, post_id, author_id, body, posted_with_pick, parent_comment_id, created_at` | `anon, authenticated` — `using (true)` |
| `prompt_responses` | `id, post_id, slot_id, profile_id, chosen_option_ids, points_earned, created_at` | `authenticated` only, `profile_id = auth.uid()` — **own rows only, at the database**, regardless of what the client filters for |
| `profiles` | `id, display_name` (author lookups only) | `anon, authenticated`, narrowed to profiles that have authored a `prompt_post` or `prompt_comment` |

`private.prompt_slot_answers` has no REST exposure whatsoever — not a
narrower policy, no policy at all, and every grant revoked. There is no path
to it except through `resolve_post` on the server.

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
