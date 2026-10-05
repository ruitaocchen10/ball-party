# Webapp

The Next.js (App Router) front end for Ball Party. What the product is and how
the pieces fit: [`docs/app.md`](../docs/app.md) and
[`docs/architecture/architecture.md`](../docs/architecture/architecture.md).
Game rules live in the database, so this app renders state and calls RPCs.

## Run it locally

```sh
supabase start                       # local Postgres, Auth and Realtime
cp .env.example .env.local           # fill in from `supabase status`
npm --prefix webapp install
npm --prefix webapp run db:reset     # migrations, seed and team logos
npm --prefix webapp run dev          # http://localhost:3000
```

`db:reset` is the complete local reset; plain `supabase db reset` leaves the
`team-logos` bucket empty. A new game schema needs `supabase stop && supabase
start` to be exposed locally (see [`supabase/README.md`](../supabase/README.md)).

To use `/admin` locally, set `PROMPTS_ADMIN_EMAILS` in `.env.local` and run
`npm run admin:sync-local`.

## Commands

`npm test` (Vitest), `npm run lint`, `npm run build`.

## Layout

- `app/`: routes (Huddle at `/`, `party`, `solo`, `lobby/[code]`, `match/[id]`, `profile`, `admin`).
- `lib/` and `components/`: split by module, mirroring the architecture
  (`foundation`, `platform`, `runtime`, `games/<game>`).
- `lib/platform/orchestration/catalog.ts`: the game catalog (which games are live, solo or room).
- `lib/supabase/database.types.ts`: generated types for the schema.
