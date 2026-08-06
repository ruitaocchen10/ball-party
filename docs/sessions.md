# Sessions and lobbies

How a group of people gets from "let's play" to four clients driving the same
authoritative game state. Shared by every game in [`games/`](./games/); see
[`architecture.md`](./architecture.md) for the stack this assumes.

### Core idea

A **session** is a durable room with a short code and up to four seats. A
**game** is one playthrough inside it. Arcade mode is a session that runs
exactly one game and ends; party mode is a session that runs games in a loop,
accumulating points, until someone hits the target.

That's the whole reason to separate the two concepts. If arcade were its own
code path we'd write joining, seating, reconnect, and host handling twice.
Instead arcade is party with the loop turned off, and the entire session layer
gets built once.

```
  sessions ──┬── session_players   (seats, names, party score)
             └── games ──┬── auction_lots / wavelength_rounds / …
                         └── …_secrets  (per-player hidden state)
```

### Decided

**Identity — Supabase anonymous auth.** This closes the open question in
[`2v2_wavelength.md`](./games/2v2_wavelength.md).

`signInAnonymously()` returns a real signed JWT with a real `auth.users` row, so
`auth.uid()` works and RLS has something trustworthy to check. The alternative —
a UUID the client generates and sends along — is unauthenticated by
construction: nothing stops a client claiming to be the psychic and reading the
target. Every hidden-information rule in this app rests on `auth.uid()` being
unforgeable, so the identity has to be server-issued.

The friction cost is zero. There is no signup screen; the client calls it on
first load, the token persists in local storage, and a refresh lands you back in
your seat. Not a one-way door either — anonymous users can be upgraded to a real
email login later against the *same* user id, so party history survives if we
ever want accounts.

Accepted cost: clearing browser data or switching devices loses the identity.
For a ten-minute party game, fine.

Anonymous users carry the `authenticated` Postgres role like everyone else, with
an `is_anonymous` claim in the JWT. If we ever add permanent-user-only tables,
they need `(auth.jwt()->>'is_anonymous')::boolean is false` as a restrictive
policy. Worth knowing now so no policy is written assuming `authenticated`
means "signed up".

**Room codes — 4 characters, recycled.** Alphabet `ABCDEFGHJKMNPQRSTUVWXYZ23456789`
— 31 symbols, with `I`/`O`/`0`/`1` dropped so nothing is ambiguous read aloud
across a room. 4 characters is ~920k combinations.

Uniqueness is only enforced over *live* sessions:

```sql
create unique index sessions_active_code
  on sessions (code) where status <> 'finished';
```

Generate, insert, retry on unique violation. Codes are a scarce human-readable
resource and there is no reason to burn them permanently on a game that finished
last March.

**Schema.**

```sql
sessions (
  id          uuid primary key,
  code        text not null,
  mode        text not null,        -- 'arcade' | 'party'
  status      text not null,        -- 'lobby' | 'in_game' | 'intermission' | 'finished'
  host_id     uuid not null references auth.users,
  current_game_id uuid references games,
  target_score int,                 -- party mode only
  created_at  timestamptz default now(),
  expires_at  timestamptz
)

session_players (
  session_id   uuid references sessions on delete cascade,
  user_id      uuid references auth.users,
  seat         smallint not null check (seat between 0 and 3),
  display_name text not null,
  party_score  int not null default 0,
  joined_at    timestamptz default now(),
  primary key (session_id, user_id),
  unique (session_id, seat)
)

games (
  id             uuid primary key,
  session_id     uuid references sessions on delete cascade,
  kind           text not null,     -- 'auction' | 'wavelength' | …
  ordinal        int not null,
  status         text not null,     -- 'setup' | 'active' | 'complete'
  phase          text,              -- game-specific
  phase_deadline timestamptz
)
```

**Seats are load-bearing, not cosmetic.** The auction rotates the right to open
a lot by seat, and Wavelength pairs seats `0+2` against `1+3`. So seat numbers
have to be stable for the life of the session and assigned without gaps. That
makes seat assignment the one genuinely concurrent write in the lobby, and it
gets a `unique (session_id, seat)` constraint plus a row lock rather than a
hopeful `count(*) + 1`.

**Session actions are Postgres functions, not Edge Functions.** This sharpens
`architecture.md`, which says game logic lives in Edge Functions.

The useful line is not "logic vs. data", it's **whether the operation reaches
outside Postgres**:

- One atomic transaction over data already in Postgres → `SECURITY DEFINER`
  Postgres function. `join_session` is the case in point: two people tapping
  join on the last seat is a race, and in Postgres the fix is `select … for
  update` on the session row for free. An Edge Function would have to open a
  transaction to do the same thing, over an extra network hop.
- External I/O or real computation → Edge Function. Building the auction lot
  pool from nflverse, drawing and shuffling the prompt bank, anything with a
  fetch in it.

Session lifecycle is entirely the first kind:

```
create_session(mode)              → code
join_session(code, name)          → session_id | typed error
leave_session(session_id)
start_game(session_id, kind)      → host only
```

All of them validate server-side and are the only write path — clients get no
direct `insert`/`update` grant on these tables at all.

**State machine.**

```
   create_session
        │
        ▼
    ┌────────┐  start_game   ┌──────────┐  game over   ┌──────────────┐
    │ LOBBY  │ ────────────▶ │ IN_GAME  │ ───────────▶ │ INTERMISSION │
    └────────┘               └──────────┘              └──────────────┘
                                                    arcade │     │ party,
                                             or target hit │     │ next game
                                                           ▼     ▼
                                                     ┌──────────┐ (back to
                                                     │ FINISHED │  IN_GAME)
                                                     └──────────┘
```

Arcade never visits `intermission` twice. Party loops through it, showing the
meta scoreboard, until `party_score >= target_score`.

**Hidden state lives in its own rows, never its own columns.** This corrects the
plan in `2v2_wavelength.md`, which currently says the target sits in a column
that RLS exposes to the psychic alone. RLS cannot do that.

RLS is *row*-level: a `using` clause decides whether you see a row, not which of
its columns. Postgres does have column-level security, but it's `GRANT`-based
and therefore per-*role* — and the psychic and the three non-psychics are all
the same `authenticated` role. There is no grant that separates them. Worse, the
failure is silent and in the wrong direction: Realtime ships the whole row to
every subscriber who can see it, so a target column on an otherwise-public round
row is broadcast to the table.

So secrets get their own table, one row per person entitled to the secret:

```sql
create table wavelength_secrets (
  round_id   uuid references wavelength_rounds on delete cascade,
  psychic_id uuid references auth.users,
  target_pos numeric not null,
  primary key (round_id)
);

alter table wavelength_secrets enable row level security;

create policy "psychic reads own target"
  on wavelength_secrets for select to authenticated
  using (psychic_id = (select auth.uid()));
```

Now row-level RLS does exactly the job the rotating screen does in the physical
game, and Realtime never has the row to fan out in the first place. The
auction's pre-reveal fantasy points take the same shape — held out of any row
the client can read until selection flips them into the public lot row.

**Membership and liveness are different things, stored differently.**

- **Membership** is durable: rows in `session_players`. Survives refresh,
  owns seats and scores.
- **Liveness** is ephemeral: Realtime **Presence** on the session channel. Who
  has a tab open *right now*.

The tempting shortcut — a `connected boolean` on `session_players` that the
client sets — is broken, because the write that sets it back to `false` is the
one write a closed laptop never sends. The flag sticks on `true` forever and the
lobby waits on a ghost. Presence is server-tracked with its own timeout, so it
handles the ungraceful exit that is the *normal* way people leave a party game.

The lobby renders membership rows, dimmed when presence is missing.

The two phases also get different departure rules: leaving during `lobby`
deletes your row and frees the seat; dropping during `in_game` holds your seat
so you can come back to it.

**Realtime — one channel per session,** topic `session:<id>`, carrying both:

- **Postgres Changes** on `sessions` and `session_players`, filtered
  `session_id=eq.<id>`. These already respect table RLS, which is why the
  secrets-in-their-own-table rule above is the whole security story.
- **Presence** on the same channel. Note this half does *not* inherit table RLS
  — private-channel Broadcast and Presence authorize against policies on
  `realtime.messages`, keyed on `realtime.topic()`. Separate policy, easy to
  forget.

Postgres Changes re-evaluates RLS per subscriber per change, which scales badly
at high fanout and is completely irrelevant at four players.

**Timers are server-authoritative deadlines, not countdowns.** The server writes
`games.phase_deadline` when a phase opens. Clients render a countdown *derived*
from it and never decide anything; every mutating RPC re-checks
`now() < phase_deadline` and rejects late actions.

Expiry is advanced by an idempotent `advance_phase(game_id)` that no-ops unless
`now() >= phase_deadline`. Any client may call it — first one wins, the rest are
harmless. This avoids both trusting a single client's clock and needing a
per-game server process. A `pg_cron` sweeper every ~10s is the backstop for the
case where every client is gone, and also expires abandoned sessions.

**RLS helper, and the recursion trap.** Nearly every policy needs "is the caller
in this session". Written inline as a subquery against `session_players`, the
policy *on* `session_players` recurses and Postgres errors out. The fix is a
`SECURITY DEFINER` function, which runs with RLS bypassed:

```sql
create function is_session_member(sid uuid) returns boolean
  language sql security definer stable as $$
    select exists (
      select 1 from session_players
      where session_id = sid and user_id = auth.uid()
    );
  $$;
```

Everything keys off that.

**Host** is seat 0 at creation. Host powers: start the game, pick the next game
in party mode. If the host leaves during `lobby`, promote the lowest occupied
seat.

**Rejoin.** On load, the persisted anonymous token is used to look for an
active `session_players` row; if one exists, offer "Rejoin XYZ4" instead of the
create/join screen. This falls out of anonymous auth for free and is the main
practical reason it beats a client-generated id.

### Open questions

- [ ] **Host migration mid-game** — lobby promotion is decided, but if the host
      drops during `in_game`, does the party pause, auto-promote, or carry on
      with nobody able to advance to the next game?
- [ ] **Reconnect grace period** — a seat is held on disconnect, but for how
      long, and what acts on that player's behalf meanwhile? Auto-pass is
      obvious for the auction and meaningless for Wavelength, where a missing
      psychic stalls the whole round.
- [ ] **Permanent quits** — does a session play on with 3, backfill from the
      lobby, or end? Wavelength is 2v2 and structurally can't lose a player.
- [ ] **Fewer than 4 players** — is 3 a legal session? The auction works;
      Wavelength does not.
- [ ] **Mid-game joins and spectators** — the seat model says no. Confirm.
- [ ] **Next-game selection in party mode** — host picks, group votes, or
      random?
- [ ] **Party point mapping** — how each game's result converts to
      `party_score`. Cross-cutting; flagged in every game doc.
- [ ] **Display names** — uniqueness within a session, length cap, and whether
      anything filters them.
- [ ] **Abuse** — rate limit on `create_session`, since anonymous auth means
      account creation is free and unlimited by design.
