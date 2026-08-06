# Architecture

App-wide technical decisions shared by every game in [`games/`](./games/).
Game-specific rules live in their own docs.

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
