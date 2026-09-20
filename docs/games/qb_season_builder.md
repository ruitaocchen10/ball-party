# QB Season Builder — game API

The server-authoritative run loop for the solo game specified in issue #72:
draft a quarterback season one trait at a time over six rounds. This document
covers what issue #74 built — start, spin, pick, respin, modes. Season
generation, the result and the share card are later tickets; a run whose six
slots are filled is simply *ready to finish*.

Implemented in migrations `0120`–`0122`, tested in
`supabase/tests/0120`–`0123_qb_season_builder_*.test.sql`. Exposed through
PostgREST as `supabase.schema("qb_season_builder").rpc(...)`; the schema must
also be listed under Exposed schemas on the hosted project (see
`supabase/README.md`).

## Rules the API enforces

- Six rounds, one per slot: `accuracy`, `arm_talent`, `mobility`, `iq`,
  `build`, `supporting_cast`. Each slot is filled exactly once.
- Each round deals a stored spin: a random team-season from 2006–2025 that has
  at least one qualifying quarterback. The same team-season may come up again
  in a later round. A round's spin is dealt when the round **opens**; a future
  round's spin does not exist to be read.
- A pick names one open slot and one source on the current spin. For a
  quarterback quality the slot is the quality and the source is the
  quarterback (`p_player_id`); for `supporting_cast` the source is the team and
  there is no quarterback.
- One respin per run. It rerolls the whole spin (it never lands on the spin it
  replaces), is final, and can be used at the start of any round. The replaced
  spin is kept, since the player saw it.
- Mode is `visible` (default) or `hidden`, chosen at start and locked. In a
  hidden run no quarterback-quality or Supporting Cast value is returned until
  the match is `complete`; visible runs always return them.
- Identity is `auth.uid()`, never an argument. Guests may play. Nothing sweeps
  an unfinished run and there is no "continue" entry point: `state` on the
  run's match id is how a run is reopened.

## Calls

Errors are `raise exception '<message>' using errcode '<code>'`; the client
matches the **message**.

### Getting a run

```ts
const { data: match } = await supabase.rpc("start_solo_run", { p_game: "qb_season_builder" })
const { data: board } = await supabase.schema("qb_season_builder")
  .rpc("start", { p_match_id: match.id, p_mode: "hidden" }) // p_mode optional, default "visible"
```

`start_solo_run` always creates a new run, so starting again is a new game.
`start` rejects: no session → `not_authenticated` (42501); mode not
`visible`/`hidden` → `invalid_mode` (22023); unknown match → `match_not_found`
(P0002); another game's match → `wrong_game`; caller not in the run →
`not_a_participant` (42501); match not in setup → `match_not_setup`.

### `state(p_match_id uuid) returns board`

Rejects: caller not in the run → `not_a_participant`; run not dealt yet →
`match_not_started` (P0002).

```
board {
  match_id, mode, phase ('picking' | 'ready_to_finish'),
  round_count (6), current_round, respin_used,
  franchise_code, season,   -- the current spin; null when ready_to_finish
  options jsonb,            -- null when ready_to_finish
  picks jsonb
}

options = { "quarterbacks": [{ "player_id", "display_name",
                               "values": { "accuracy", "arm_talent", "mobility", "iq", "build" } | null }],
            "supporting_cast": { "value": n | null } }

picks   = [{ "round", "slot", "franchise_code", "season",
             "player_id" | null, "display_name" | null, "value": n | null }]   -- oldest first
```

Every `values` / `value` is `null` in a hidden run until the match is complete.

### `pick(p_match_id uuid, p_slot text, p_player_id text default null) returns board`

Deals the next round's spin in the same transaction; after the sixth pick the
run is `ready_to_finish`. Rejects, in order: `not_authenticated`;
`invalid_slot` (22023); `match_not_found`; `wrong_game`; `not_a_participant`;
`match_not_playing` (P0001); `draft_complete`; `slot_filled`; `invalid_source`
(22023 — a quality without a quarterback, or the Supporting Cast with one);
`source_not_on_spin` (the quarterback is not on the current spin).

`pick` and `respin` can also raise `pool_exhausted` (P0001) if a spin cannot
be drawn, which only happens when the ratings tables hold no qualifying
quarterback-season (or, for a respin, no team-season other than the current one).

### `respin(p_match_id uuid) returns board`

Rejects: `not_authenticated`; `match_not_found`; `wrong_game`;
`not_a_participant`; `match_not_playing`; `draft_complete`; `respin_used`.

## What a client can read

Client-readable through RLS, for the run's owner only (guests included):
`qb_season_builder_matches` (mode, round, respin spent), `qb_season_builder_spins`
(only rounds up to the current one) and `qb_season_builder_picks` (slot and
source, never a value). Everything numeric lives in `qb_season_builder_private`
— `qb_seasons`, `team_seasons` and `pick_values` — which no client role can
reach; a value leaves the database only through `state` / `pick` / `respin`,
which decide per run whether to show it.

Two things the finish ticket and the pipeline ticket should know:

- **Reveal of passed options.** Values are hidden until the match is `complete`,
  which nothing in this ticket does, so a hidden run shows no values even after
  its sixth pick. `state` returns the values of the *picks* once complete; it
  does not yet return the options that were passed on. Every spin the player
  saw is kept (`qb_season_builder_spins`, including a respun-away attempt 1) so
  the finish ticket can build that reveal.
- **Reloading ratings mid-run.** Options are read live from the rating tables,
  but a pick's value is copied at pick time (`pick_values`). A pipeline reload
  while runs are in flight can therefore change what an unpicked option shows,
  or remove it from a spin (`source_not_on_spin`). Runs are short, but load the
  data at a quiet moment or snapshot options at deal time if that matters.

The rating tables are loaded by the ratings pipeline ticket. Until then a fresh
local database carries a few made-up placeholder rows from `seed.sql`.
