# QB Season Builder — game API

The server-authoritative run loop for the solo game specified in issue #72:
draft a quarterback season one trait at a time over six rounds. This document
covers what issue #74 built — start, spin, pick, respin, modes — and what issue
#77 added on top: finishing a run into a generated, saved, shareable season, and
the personal best. The share card is a later ticket.

Implemented in migrations `0120`–`0122` and `0127`, tested in
`supabase/tests/0120`–`0122` and `0127_qb_season_builder_*.test.sql`. Exposed through
PostgREST as `supabase.schema("qb_season_builder").rpc(...)`; the schema must
also be listed under Exposed schemas on the hosted project (see
`supabase/README.md`).

## Rules the API enforces

- Six rounds, one per slot: `accuracy`, `arm_talent`, `mobility`, `iq`,
  `build`, `supporting_cast`. Each slot is filled exactly once.
- Each round deals a stored spin: a random team-season from 2006–2025 that has
  at least one qualifying quarterback. A team-season can be shown only once per
  run, including one replaced by a respin. A round's spin is dealt when the
  round **opens**; a future round's spin does not exist to be read.
- A pick names one open slot and one source on the current spin. For a
  quarterback quality the slot is the quality and the source is the
  quarterback (`p_player_id`); for `supporting_cast` the source is the team and
  there is no quarterback.
- One respin per run. It rerolls the whole spin (it never lands on the spin it
  replaces), is final, and can be used at the start of any round. The replaced
  spin is kept, since the player saw it.
- Mode is `visible` (default) or `hidden`, chosen at start and locked. In a
  hidden run no quarterback-quality or Supporting Cast value is returned until
  the match is `complete` (which is what `finish` does); visible runs always
  return them.
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
  match_id, mode, phase ('picking' | 'ready_to_finish' | 'complete'),
  round_count (6), current_round, respin_used,
  franchise_code, season,   -- the current spin; null when ready_to_finish or complete
  options jsonb,            -- null when ready_to_finish or complete
  picks jsonb,
  shown jsonb               -- null until complete: every spin the player was shown
}

options = { "quarterbacks": [{ "player_id", "display_name",
                               "values": { "accuracy", "arm_talent", "mobility", "iq", "build" } | null }],
            "supporting_cast": { "value": n | null } }

picks   = [{ "round", "slot", "franchise_code", "season",
             "player_id" | null, "display_name" | null, "value": n | null }]   -- oldest first
```

Every `values` / `value` is `null` in a hidden run until the match is complete.

```
shown = [{ "round", "attempt", "franchise_code", "season", "options" }]   -- oldest first
```

`shown` is the reveal: once the run is finished, every spin the player saw with
every option's values, in either mode. That includes the quarterbacks passed on and
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
  picks [{ round, slot, franchise_code, season, player_id, display_name, value }] }
```

Only blended values: never a source rating and never the seed. The result is saved
as it was generated, so retuning the model later does not change a saved link. The
values of options that were passed on are not in it; the owner reads them from
`state` (`shown`).

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
source, never a value). Everything numeric lives in `qb_season_builder_private`
— `qb_seasons`, `team_seasons`, `pick_values`, the season model and
`season_results` (the saved seasons **and their seeds**) — which no client role can
reach; a value leaves the database only through `state` / `pick` / `respin` /
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
pipeline (`scripts/qb_ratings/`, issue #75), so a fresh local database is
playable after `npm --prefix webapp run db:reset`. The source ratings the values
were blended from sit beside them in `qb_season_builder_private.madden_ratings`,
unreachable by any client role and never returned by any call; a hand overrides
table (`rating_overrides`) corrects values the formulas get clearly wrong.

## The season model

Season generation (issue #77) turns the six picked values into a season with a
model fitted offline on the real 2006-2025 seasons (issue #76). It is data, in
`qb_season_builder_private.season_model_*` (migrations `0125` schema and `0126`
data (retuned by later data migrations, the newest being the whole truth), generated by `scripts/qb_season_model/`, see its README), and like the
ratings no client role can read it. It holds:

- a formula per output (`attempts`, `comp_pct`, `ypa`, `td_rate`, `int_rate`,
  `rush_yards`, `rush_td`, `wins`), each linear in the six values on a link scale.
  Yards, touchdowns, interceptions and rating are derived from them. The formulas
  extrapolate, so a top-of-scale build can beat any real season, while wins can
  never pass 17, a rate can never go negative and attempts saturate (a logit link capped
  at 670, where a straight line asked for 700+ from a build stacked with 90s);
- the real residual around each formula as a quantile table plus a per-output
  `noise_scale` (0.8 for wins, 0.5 for the quarterback's line), so noise is bounded by
  what really happened and lands mostly on team outcomes;
- a five-rung playoff ladder, each rung a logistic in wins. The first rung also carries
  guarantees (`never_to`, `always_from`): 12 or more wins is always a playoff team and 5 or
  fewer never is, as it was for every real team, because a logistic alone let a 13-4 team miss
  about 1 time in 520 (migration `0139`, values from `LADDER_GUARANTEES` in the fit's config);
- a threshold for each award, calibrated on the real winners' seasons, with the
  winners' spread for noise near the edge, and the award it requires, if any (the MVP
  needs the All-Pro, and the All-Pro and Offensive Player of the Year the Pro Bowl,
  as in the real data: 17 of 18 MVPs were All-Pro). All-Pro is judged on wins as well
  as the stat line, so a 13-win, 4,500-yard season is a real MVP candidate;
- the score: how the real seasons spread on stat line, team success and awards, and
  the 55 / 30 / 15 weights that mix them, and a soft ceiling on the mixed score (a
  `score_curve`: see below);

How to read each table is written at the top of `0125`. All of it is per full
17-game season. Every weight, bound, noise scale and threshold is configuration in
`scripts/qb_season_model/config.py`.

## Season generation

`finish` reads the model above with the run's six picked values and a seed drawn at
that moment (`qb_season_builder_private.finish_run(match, seed)` is the same thing
with a chosen seed, for tests). In order:

1. each output's formula over the six values as the game counts them (a value counts in full
   up to 70 and only 0.85 of each point above it, the difficulty setting `VALUE_CURVE`,
   migration `0146`), plus its noise: a draw from the output's residual table
   scaled by `noise_scale`, added before the inverse link. The stat line is derived
   from the outputs and rounded (counts to whole numbers; wins rounded, losses the
   rest of 17). The record's draw follows how the quarterback happened to play: it is
   correlated (0.3, `WINS_LINE_LINK`, migration `0144`) in normal scores with the draws of
   yards per attempt, touchdown rate, interception rate (reversed) and completion %, so a
   better line than his values predicted tends to come with more wins, and the record's own
   spread and a build's average record do not change;
2. the playoff ladder, walked rung by rung at the season's wins until one is missed (a rung
   with a guarantee is cleared or missed outright at those wins, whatever the draw);
3. each award: its score, nudged by up to `noise_scale` of the winners' spread either
   way, against its threshold, judged in order of what it requires (Pro Bowl, All-Pro,
   Offensive Player of the Year, MVP) so a season never has an award without the one it
   depends on; Super Bowl MVP needs the title (migration `0136` added the requirement);
4. the score: the season's percentile on each component (share of real seasons it is
   strictly better than), mixed by the score weights, then held to the soft ceiling and
   capped at 100. The ceiling (migration `0141`, values in the fit's `SCORE_CURVE`) leaves a
   score at or below its `start` (70) alone and above it makes the top harder:
   `start + (100 - start) * ((score - start) / (100 - start)) ^ exponent` (1.6), so a mixed 90
   reads 86 and 0 and 100 stay put. Every component's points are scaled by the same factor,
   so the breakdown still adds up to the score;

Every random draw is a hash of the seed and a name (`unit_draw`), so **the same picks
and the same seed always give the same season**, independent of the order draws are
made in. It is deliberately not `setseed()`, which would leave the connection's
`random()` predictable for whoever uses it next. The seed lives in
`qb_season_builder_private.season_results` beside the saved result and is never
returned by any call.

Two things to know about the model:

- **The numbers are a regression to the mean.** The six values explain about half
  of a quarterback's passing yards and 60% of a team's wins, so a quarterback's own
  six values fit to a good season, not a copy of his real one (a record-setting
  5,476-yard year fits at about 4,200). Noise is drawn from the real spread and
  bounded by it. Do not add more variance than the residual tables carry.

## The web UI

Three screens, all reading the calls above and deciding nothing themselves.

- **The pick screen** (`components/games/qb-season-builder/QbSeasonBuilderMatch.tsx`,
  at `/match/[id]`): this round's spin and the six slots. Once all six are filled it
  offers **Reveal my season**, which is `finish` followed by `router.refresh()` —
  the page is rendered on the server from the run, and a `complete` run renders as
  the reveal below. A `match_not_playing` refusal there is not an error: the run is
  already finished (another tab, or a lost answer to an earlier click), and the
  reveal is where the player should land.
- **The staged reveal** (`QbSeasonBuilderResult.tsx` with `staged`, same URL once
  the run is `complete`): stat line, record, playoffs, awards, then the score, a
  step at a time, and only then the breakdown, the per-pick recap and the closest
  real season. The score holds a beat on its own — it is what the four steps
  before it build to, so what explains it waits. The order and the one-time-ness
  live in `lib/games/qb-season-builder/useSeasonReveal.ts`, a hook with its own
  suite, as for sabotage draft's `useTurnReveal` and the auction's `useLotReveal`.
  It can be skipped to the end, and it plays **once**: watched through or skipped,
  the hook remembers the run in `localStorage` so a reload goes straight to the
  finished state. That is a per-browser convenience and nothing more — blocked or
  cleared storage, or a second device, costs a replay, which is why it is not on
  the run.
  In a hidden run this screen also shows **every option the player saw** with its
  value, the ones passed on and a respun-away spin included. That is the board's
  `shown`, which only the run's owner can read, so it is not on the public page.
- **The public result** (`/solo/qb-season-builder/result/[id]`): the same component
  unstaged, from `result` alone. Reachable signed out — the path is in the proxy's
  public list and the run's id is the whole capability — so a link works for a
  stranger and for a guest's run alike. `noindex`, for the same reason.

The personal best is the **viewer's** own, never the run owner's: it is read for the
run's mode and only for a signed-in account, since the stat is an account feature
and RLS refuses a guest the row. A guest gets the nudge to make an account instead.
