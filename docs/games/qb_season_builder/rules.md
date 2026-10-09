# QB Season Builder — game API

The server-authoritative run loop for the solo game: draft a quarterback season
one trait at a time over six rounds, then finish the run into a generated,
saved, shareable season with a score and a personal best.

Exposed through PostgREST as `supabase.schema("qb_season_builder").rpc(...)`;
the schema must also be listed under Exposed schemas on the hosted project (see
`supabase/README.md`). Tested in `supabase/tests/*qb_season_builder_*.test.sql`.

## Rules the API enforces

- Six rounds, one per slot: `accuracy`, `arm_talent`, `mobility`, `iq`,
  `build`, `supporting_cast`. Each slot is filled exactly once.
- Each round deals a stored spin: a random team-season from the run's era that
  has at least one qualifying quarterback. A team-season can be shown only once
  per run, including one replaced by a respin. A round's spin is dealt when the
  round **opens**; a future round's spin does not exist to be read.
- A pick names one open slot and one source on the current spin. For a
  quarterback quality the slot is the quality and the source is the
  quarterback (`p_player_id`); for `supporting_cast` the source is the team and
  there is no quarterback.
- One respin per run. It rerolls the whole spin (it never lands on the spin it
  replaces), is final, and can be used at the start of any round. The replaced
  spin is kept, since the player saw it.
- Mode is `visible` (default) or `hidden`, chosen at start and locked. In a
  hidden run no quarterback-quality or Supporting Cast grade is returned until
  the match is `complete` (which is what `finish` does); visible runs always
  return them.
- What a client is told is a **letter grade**, A+ to F, never the blended value
  behind it. The mapping is `qb_season_builder_private.grade_of`
  and happens in the two projections every board is built from, so no number is in
  the payload in either mode. Five points a grade, tuned to the real spread of the
  data (25 to 99, median 61): A+ 95–99, A 90–94, A- 86–89, B+ 82–85, B 78–81,
  B- 74–77, C+ 70–73, C 65–69, C- 60–64, D+ 55–59, D 50–54, D- 45–49, F 44 and
  below. The season model still runs on the values; only what is shown changed.
- Era is `all` (2006–2025, default), `classic` (2006–2015) or `modern`
  (2016–2025), chosen at start and locked the same way as mode — three fixed
  presets a client hardcodes rather than a free range, see migration `0153`'s
  header for why. It narrows every deal (the opening one, a pick's next round,
  a respin's reroll) to that window; nothing else about the rules changes,
  since the season model scores the six picked values, never the year they
  came from.
- Identity is `auth.uid()`, never an argument. Guests may play, and a visitor
  with no session at all is made one when they start a run (`playSolo` signs
  them in anonymously first). A guest's runs are swept by the nightly
  `private.cleanup_guest_accounts` (migration `0155`): a finished run 30 days after
  it ended, an unfinished one a day after it started. There is no "continue"
  entry point: `state` on the run's match id is how a run is reopened, while it
  lasts.

## Calls

Errors are `raise exception '<message>' using errcode '<code>'`; the client
matches the **message**.

### Getting a run

```ts
const { data: match } = await supabase.rpc("start_solo_run", { p_game: "qb_season_builder" })
const { data: board } = await supabase.schema("qb_season_builder")
  .rpc("start", { p_match_id: match.id, p_mode: "hidden", p_era: "classic" })
  // p_mode optional, default "visible"; p_era optional, default "all"
```

`start_solo_run` always creates a new run, so starting again is a new game.
`start` rejects: no session → `not_authenticated` (42501); mode not
`visible`/`hidden` → `invalid_mode` (22023); era not `all`/`classic`/`modern` →
`invalid_era` (22023); unknown match → `match_not_found` (P0002); another
game's match → `wrong_game`; caller not in the run → `not_a_participant`
(42501); match not in setup → `match_not_setup`.

### `state(p_match_id uuid) returns board`

Rejects: caller not in the run → `not_a_participant`; run not dealt yet →
`match_not_started` (P0002).

```
board {
  match_id, mode, era ('all' | 'classic' | 'modern'),
  phase ('picking' | 'ready_to_finish' | 'complete'),
  round_count (6), current_round, respin_used,
  franchise_code, season,   -- the current spin; null when ready_to_finish or complete
  options jsonb,            -- null when ready_to_finish or complete
  picks jsonb,
  shown jsonb               -- null until complete: every spin the player was shown
}

options = { "quarterbacks": [{ "player_id", "display_name",
                               "grades": { "accuracy", "arm_talent", "mobility", "iq", "build" } | null }],
            "supporting_cast": { "grade": g | null } }     -- g is "A+" … "F"

picks   = [{ "round", "slot", "franchise_code", "season",
             "player_id" | null, "display_name" | null, "grade": g | null }]   -- oldest first
```

Every `grades` / `grade` is `null` in a hidden run until the match is complete.

```
shown = [{ "round", "attempt", "franchise_code", "season", "options" }]   -- oldest first
```

`shown` is the reveal: once the run is finished, every spin the player saw with
every option's grades, in either mode. That includes the quarterbacks passed on and
a spin thrown away by the respin (`attempt` 1 of a round that has an `attempt` 2).

### `pick(p_match_id uuid, p_slot text, p_player_id text default null) returns board`

Deals the next round's spin in the same transaction; after the sixth pick the
run is `ready_to_finish`. Rejects, in order: `not_authenticated`;
`invalid_slot` (22023); `match_not_found`; `wrong_game`; `not_a_participant`;
`match_not_playing` (P0001); `draft_complete`; `slot_filled`; `invalid_source`
(22023 — a quality without a quarterback, or the Supporting Cast with one);
`source_not_on_spin` (the quarterback is not on the current spin).

`pick` and `respin` can also raise `pool_exhausted` (P0001) if a spin cannot
be drawn, which only happens when the ratings tables hold no qualifying
team-season the player has not already been shown.

### `respin(p_match_id uuid) returns board`

Rejects: `not_authenticated`; `match_not_found`; `wrong_game`;
`not_a_participant`; `match_not_playing`; `draft_complete`; `respin_used`.

### `finish(p_match_id uuid) returns jsonb`

Turns the six picked values into a season, saves it and completes the match. The
seed is drawn here and is not an argument. Returns the saved result (below).
Rejects: `not_authenticated`; `match_not_found`; `wrong_game`; `not_a_participant`;
`match_not_playing` (a finished run is no longer playing, so a second `finish`
raises this; read the result with `result`); `draft_incomplete` (P0001 — a slot is
still open). One run has exactly one saved result.

### `result(p_match_id uuid) returns jsonb`

The saved result of a finished run. **Callable by anyone, signed out included**: the
run's id is the whole capability, so the link to a run's result works for a stranger
and for a guest's run alike. Rejects `result_not_found` (P0002) for a run with none.

```
{ match_id, mode,
  stat_line { attempts, completions, pass_yards, pass_tds, interceptions, rating,
              rush_yards, rush_tds },
  record { wins, losses },                       -- of 17
  playoffs { depth 0..5, result },               -- missed_playoffs | lost_wild_card |
                                                 -- lost_divisional | lost_conference |
                                                 -- lost_super_bowl | won_super_bowl
  awards { mvp, opoy, all_pro, pro_bowl, sb_mvp },
  score,                                         -- 0..100, one decimal
  breakdown [{ component, weight, percentile, points }],   -- points add up to score
  picks [{ round, slot, franchise_code, season, player_id, display_name, grade }] }
```

Only grades: never a blended value, a source rating or the seed. The result is saved
as it was generated, so retuning the model later does not change a saved link. A
result saved before `0154` stored a `value` on each pick; `result` grades it on the
way out, so an old link reads the same as a new one. The grades of options that were
passed on are not in it; the owner reads them from `state` (`shown`).

### The personal best

`public.qb_season_builder_player_stats (user_id, mode, best_score)`: one row per
player per mode, raised by `finish` and by nothing else, so a run in play has no
score and a worse run never lowers it. Readable only by its owner and only when
signed in with an account (guests are refused, as for Higher or Lower's stat). A
guest's best is still recorded against their user id.

## What a client can read

Client-readable through RLS, for the run's owner only (guests included):
`qb_season_builder_matches` (mode, round, respin spent), `qb_season_builder_spins`
(only rounds up to the current one) and `qb_season_builder_picks` (slot and
source, never a value or a grade). Everything numeric lives in `qb_season_builder_private`
— `qb_seasons`, `team_seasons`, `pick_values`, the season model and
`season_results` (the saved seasons **and their seeds**) — which no client role can
reach; a grade (never a value) leaves the database only through `state` / `pick` / `respin` /
`finish` / `result`, which decide what to show. The one other client-readable table
is the personal best, for its owner only.

Two things to know about the ratings:

- **Reveal of passed options.** Values are hidden until the match is `complete`,
  which `finish` does. `state` then returns every spin the player saw in `shown`
  (`qb_season_builder_spins` keeps a respun-away attempt 1 for exactly this).
- **Reloading ratings mid-run.** Options are read live from the rating tables,
  but a pick's value is copied at pick time (`pick_values`). A pipeline reload
  while runs are in flight can therefore change what an unpicked option shows,
  or remove it from a spin (`source_not_on_spin`), and the reveal of a finished
  run reads the rating tables live too. Runs are short, but load the data at a
  quiet moment or snapshot options at deal time if that matters.

The rating tables are loaded by migration `0124`, generated by the ratings
pipeline (`scripts/qb_ratings/`), so a fresh local database is
playable after `npm --prefix webapp run db:reset`. The source ratings the values
were blended from sit beside them in `qb_season_builder_private.madden_ratings`,
unreachable by any client role and never returned by any call; a hand overrides
table (`rating_overrides`) corrects values the formulas get clearly wrong.

## The season model

`finish` turns the six picked values into a season with a model fitted offline
on the real 2006-2025 seasons. It is data, in
`qb_season_builder_private.season_model_*`, generated by `scripts/qb_season_model/`
(see its README for the tables and every weight, bound, noise scale and
threshold, all configuration in `scripts/qb_season_model/config.py`). No client
role can read it. It holds a formula per output (attempts, completion %, yards
per attempt, TD / INT rate, rush yards and TDs, wins), residual tables for
noise, a five-rung playoff ladder, award thresholds, and the score weights
(55 stat line / 30 team success / 15 awards).

## Season generation

`finish` reads the model with the run's six values and a seed drawn at that
moment (`qb_season_builder_private.finish_run(match, seed)` takes a chosen seed,
for tests). In order:

1. **Stat line and record.** Each output's formula over the six values, plus a
   draw from its residual table scaled by `noise_scale`. A value counts in full
   up to 70 and 0.85 per point above it (`VALUE_CURVE`). The record's draw is
   correlated (0.3) with the line's draws, so a better line than predicted tends
   to come with more wins.
2. **Playoffs.** The ladder is walked rung by rung at the season's wins until
   one is missed. The first rung is guaranteed at 12+ wins and impossible at 5 or
   fewer, as it was for every real team.
3. **Awards.** Each award's score, nudged by noise, against its threshold, judged
   in order of what it requires (Pro Bowl, All-Pro, Offensive Player of the Year,
   MVP), so a season never has an award without its prerequisite. Super Bowl MVP
   needs the title.
4. **Score.** The season's percentile on each component, mixed by the weights,
   then held to a soft ceiling and capped at 100: above `start` (70) the score
   becomes `start + (100 - start) * ((score - start) / (100 - start)) ^ 1.6`, so a
   mixed 90 reads 86, while 0 and 100 stay put. Every component's points scale by
   the same factor, so the breakdown still sums to the score.

Every random draw is a hash of the seed and a name (`unit_draw`), so **the same
picks and seed always give the same season**, regardless of draw order. It is
deliberately not `setseed()`, which would leave the connection's `random()`
predictable. The seed lives in `qb_season_builder_private.season_results` beside
the saved result and is never returned.

**The numbers are a regression to the mean.** The six values explain about half
of a quarterback's passing yards and 60% of a team's wins, so a quarterback's
own values fit a good season, not a copy of his real one. Noise is drawn from
the real spread and bounded by it; do not add more variance than the residual
tables carry.

## The web UI

Three screens that read the calls above and decide nothing themselves.

- **Pick screen** (`QbSeasonBuilderMatch.tsx`, at `/match/[id]`): this round's
  spin and the six slots. Once all six are filled, **Reveal my season** calls
  `finish` then `router.refresh()`. A `match_not_playing` refusal there is not
  an error (another tab already finished it); the reveal is where the player
  lands.
- **Staged reveal** (`QbSeasonBuilderResult.tsx` with `staged`, same URL once
  `complete`): stat line, record, playoffs, awards, then the score, then the
  breakdown and per-pick recap. Order and once-only playback live in
  `useSeasonReveal.ts`, which remembers the run in `localStorage` (a per-browser
  convenience, so a second device costs a replay). In a hidden run it also shows
  every option the player saw with its grade (the board's `shown`, owner-only).
- **Public result** (`/solo/qb-season-builder/result/[id]`): the same component
  unstaged, from `result` alone. Reachable signed out (the run id is the whole
  capability) and `noindex`.

The personal best shown is the **viewer's**, never the run owner's, and only for
a signed-in account; a guest gets a nudge to make one.
