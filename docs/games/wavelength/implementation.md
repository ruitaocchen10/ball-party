# 2v2 Wavelength — implementation plan

> **Status:** the webapp build described here has since shipped (see the Wavelength migrations and `webapp/components/games/wavelength/`). Kept for the reasoning behind the structure; check the code for what is current.

How to build what [`rules.md`](./rules.md) decides. Webapp only
(iOS follows). This is a plan, not a spec: the rules live in the design doc, and
this says how they map onto the repo's existing patterns and in what order to
build them.

## What the repo already gives us

- **`matches.game` already allows `'wavelength_2v2'`** (migration 0078's check
  constraint), and the catalog already has a `wavelength` entry in `development`.
  No registry change is needed.
- **`start_run` already seats 2 to 4 players** and returns a `setup` match. It
  accepts a lobby of 3, so the game's own `start` must reject that (see 2v2 vs
  co-op below).
- **The schema pair pattern.** A game owns `<game>` (the write API, exposed
  through PostgREST) and `<game>_private` (the rules engine, unreachable). So:
  `wavelength` and `wavelength_private`.
- **Hidden-to-everyone-but-one-player state is a solved shape.** Sabotage Draft's
  pick (0052) and Higher or Lower's calls (0034) put the secret on a
  client-readable, Realtime-published table and restrict it with an RLS policy,
  alongside a bare "status" row everyone may see. Wavelength's target is this
  shape.
- **The timer contract.** `useMatchClock` + a game `tick` RPC that is free to be
  wrong, doubles as the presence heartbeat, and latches an `absent` flag. This is
  how Wavelength's timeouts and disconnects (design doc, Q8/Q9) are implemented.
- **`private.finish_match(match_id, scores)`** is how a game hands its result to
  the platform. It derives placement from `raw_score` alone (ties share a rank),
  and `match_players` has a `team` column.

## Decisions this plan makes by default

These weren't settled in the design session. They're chosen to fit the repo and
are worth a look before building.

1. **The target is a number, 0 to 1000, held in its own table.** Row-level
   security hides whole rows, not columns, so the target can't sit on the round
   row that everyone reads. `wavelength_targets (match_id, round, target)` is
   readable only by that round's psychic, until the guess locks and the target is
   written onto the public round row, the same write-time reveal Higher or Lower
   uses for `points`.
2. **The live needle uses Realtime Broadcast, not table writes** *(confirmed)*. The repo uses
   table-change Realtime only (no Broadcast, no Presence), so this is new. The
   needle is cosmetic and ephemeral, so the guesser's client broadcasts it a few
   times a second on the match channel. The *lock* is the only thing that goes
   through an RPC, and the server uses the position in the lock call, never a
   broadcast one. The alternative, a throttled RPC write per update, is
   consistent with the other games but costs a database write per movement.
3. **A card is hidden from everyone but its psychic until its guess turn.** The
   design doc says each player sees only their own cards in the fill phase. The
   card's endpoints and clue are therefore RLS-restricted too, and become visible
   to the table when the round opens for guessing.
4. **A match has one `wavelength_matches` row** carrying `mode` (`'versus'` or
   `'coop'`), `preset` (`'short'`, `'medium'`, `'long'`, or null for versus), the
   phase, the current round and the deadlines.
5. **Config constants live in one SQL function,** `wavelength_private.config()`:
   wedge width, clue word and character limits, the timer lengths, and the
   per-preset targets and star thresholds. Everything the design doc calls
   "tunable" is read from here, so playtesting means one migration.
6. **2v2 tiebreak is encoded into `raw_score`.** `finish_match` can only rank by
   one number. For versus, pass `team_score * 1000 + bullseyes` so a bullseye
   tiebreak falls out of the ranking, and let sudden-death rounds settle anything
   still tied before finishing. Co-op passes the plain score; win/lose and stars
   are stored in the game's own result row.

## Data model

All in `public` (client-readable, in the Realtime publication) unless noted, with
`wavelength_private` for the rules engine.

| Table | Key | Holds | Who can `select` |
| --- | --- | --- | --- |
| `wavelength_matches` | `match_id` | `mode`, `preset`, `phase`, `phase_deadline`, `current_round`, `round_count`, sudden-death counter | Match members |
| `wavelength_players` | `match_id, user_id` | `seat`, `team`, `last_seen_at`, `absent` | Match members |
| `wavelength_rounds` | `match_id, round` | `psychic_id`, `guesser_id`, `status`, the score and `revealed_target` once locked, `clue` once the round opens | Match members (clue and card fields are null until the round opens) |
| `wavelength_cards` | `match_id, round` | The two endpoint labels for this round's card | The round's psychic only, until the round opens |
| `wavelength_targets` | `match_id, round` | `target` (0 to 1000) | The round's psychic only, until locked |
| `wavelength_clue_statuses` | `match_id, round` | Existence only: "this clue is written" | Match members |
| `wavelength_results` | `match_id` | Final score, outcome, bullseye count, preset, stars | Match members |
| `wavelength_private.deck` | `card_id` | The 104 approved cards | Nobody (no policies, privileges revoked) |

The target is never part of any row or payload a non-psychic can read before the
lock. That is the property the leak test below proves.

## Phases

```
setup → (start) → fill → guessing ⇄ reveal → complete
                                 ↘ sudden_death (versus ties only)
```

- **fill** — every player writes all their clues in parallel; one deadline for
  the phase (40s × clues each). Missing clues become skipped rounds.
- **guessing** — rounds play sequentially. In versus the psychic's partner
  guesses and teams alternate; in co-op the two players alternate. 30s per guess;
  a missed guess auto-locks at the needle's last known position.
- **reveal** — the target is written to the round row; points are scored and
  everyone sees it. Then the next round opens, or the match completes.
- **sudden_death** — versus only, entered if teams are tied after the bullseye
  tiebreak. Each round gets a fresh card with its own fill and guess phases,
  repeating until one team leads.

Round counts: versus is 8; co-op is 4, 6 or 8 by preset (2, 3 or 4 psychs each).

## RPCs (`wavelength` schema)

All `security definer`, identity from `auth.uid()`, following the existing
conventions and error-message style.

| RPC | Does |
| --- | --- |
| `start(match_id, mode, preset)` | Deals the match. Rejects a mode/player-count mismatch (versus needs exactly 4, co-op exactly 2), so a lobby of 3 can't start. Draws cards without replacement, draws targets, assigns teams (random for versus) and psychic/guesser order. |
| `state(match_id)` | The full re-read the clock's reconcile calls. A named projection, never `select *`. |
| `submit_clue(match_id, round, clue)` | Validates (1 to 8 words, at most 100 characters, no digits) and writes the clue. Rejects after the fill deadline. |
| `lock_guess(match_id, round, position)` | The guesser locks a position. Scores it, writes the target to the round row, advances. |
| `tick(match_id)` | The `expire` function. Stamps the caller present, then advances any phase whose deadline has passed (skips missing clues, auto-locks missing guesses, latches absence). |

`private.finish_match` is called from inside the game's transaction when the last
round resolves.

## Build order

Each slice is one migration plus its pgTAP tests plus whatever UI it unlocks,
matching how the other games were built (a numbered migration per slice).

1. **Schema, config and deal.** Schemas, tables, `config()`, the card deck seed
   (from `cards.md`), `start`/`state`. Add `wavelength` to
   `[api] schemas` in `config.toml` **and to the hosted project's exposed-schema
   dashboard setting**, which no migration carries (see `supabase/README.md`;
   every game so far has needed this step).
2. **Hidden state and the leak test.** The RLS policies and a pgTAP leak test in
   the style of 0010: from a non-psychic's session, assert the target and
   unopened card are in no client-reachable relation or Realtime publication.
   Build this *before* any gameplay, because it's the property that ruins a game
   if it's wrong once.
3. **Fill phase.** `submit_clue`, clue validation, the fill deadline.
4. **Guess phase and scoring.** `lock_guess`, wedge scoring from the config
   width, the reveal write.
5. **Timers and presence.** `tick`, skipped rounds, auto-lock, `absent`.
6. **Finish.** Co-op win/lose and stars, versus ranking with the bullseye
   tiebreak, sudden death, `finish_match`, `wavelength_results`.
7. **Webapp lib** (`webapp/lib/games/wavelength/`): board types and parsing,
   scoring display helpers, the clue validator shared with the form.
8. **Webapp UI** (`webapp/components/games/wavelength/`): the dial and needle,
   the fill screen, the guess and reveal screens, the result screen with stars.
   Wire `WavelengthMatch` into `app/match/[id]/page.tsx`.
9. **Lobby start** (`StartWavelength`, modelled on `StartSabotageDraft`): a mode
   picker (Co-op or 2v2), the preset picker for co-op, and Start enabled only
   when the player count matches.
10. **Catalog.** Set `status: "live"` and `match` once it plays end to end.

## Tests

- **pgTAP per slice**, run with `supabase test db`. Each file rolls back and uses
  `tests.act_as` to exercise RLS as a player.
- **The leak test** (slice 2) is the load-bearing one, as above.
- **Vitest** for the clue validator, the wedge-scoring helper and the board
  parsing, in the style of the existing `lib/games/*` tests.
- **Playtesting** is the real test for wedge width and the star thresholds, which
  the design doc already marks as guesses.

## Risks

- **The live needle is new infrastructure.** Broadcast has no precedent in the
  repo, so slice 8 includes the channel setup and its failure mode (the needle
  simply doesn't move live; the lock still works).
- **`finish_match`'s single-number ranking** is the awkward fit for the versus
  tiebreak. The `team_score * 1000 + bullseyes` encoding is the workaround; if
  that feels wrong, the alternative is a platform change to let a game pass its
  own placements.
- **Hosted exposed-schema step** is easy to forget and fails as `PGRST106` in
  production only.
- **Sudden-death timers** default to the regular ones: each sudden-death round
  is one clue per team, so the fill phase is 40 seconds and the guess is 30.
  This was not discussed; change the config if it feels wrong. It no longer
  blocks slice 6.
