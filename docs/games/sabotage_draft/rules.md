# Sabotage draft

Fourteen rounds. Thirteen fill a fixed roster slot (QB, RB1, RB2, WR1-3, TE,
OL, DL, LB, CB, S, Special Teams) and the fourteenth is a wildcard shot at
upgrading one of them. Each round every player spins a random franchise and
picks any player from that franchise's history at the slot's position, any year.
Everyone else can try to guess what you picked and wreck it. Once rosters are
set, roster strength generates a simulated season record, and best record wins.
The skill is knowing team history deep enough to both pick well and call
another player's pick.

Two to four players (the lobby limit). Arcade only (see `docs/app.md`); there is no solo mode,
since the hook is other players wrecking your draft. Implemented in the
`sabotage_draft` / `sabotage_draft_private` schemas.

## Game modes

The host picks a mode at start. Everything below describes **Full**; shorter
modes change only the roster and the season yardstick, not pick, guess or
X-Factor mechanics (`sabotage_draft_private.mode_slots`,
`baseline_roster_strength(mode)`).

| Mode | Rounds | Slots |
|---|---|---|
| Full | 14 | QB, RB1, RB2, WR1-3, TE, OL, DL, LB, CB, S, ST, X-Factor |
| Standard | 10 | QB, RB1, RB2, WR1, WR2, TE, FLEX, DEF, ST, X-Factor |
| Quick | 7 | QB, RB1, WR1, TE, FLEX, DEF, X-Factor |

- **FLEX** takes any RB, WR or TE from the spun franchise.
- **DEF** takes any single DL, LB, CB or S: one player on the shared AV scale,
  not a team defense.
- **X-Factor** is the last round of every mode and may upgrade any offensive
  skill slot the mode has, FLEX included.
- **Season baseline is per mode** (Full 93, Standard 62, Quick 52), built the
  same way: the average over every real 2006-2025 team-season of that team's
  best player at each of the mode's slots. The logistic divisor scales with it
  (`25 * baseline / 93`), so a roster equally far above its own baseline wins
  about the same share in any mode. Letter grades rescale the same way.

## Round structure

**One team spin per player per slot, picks made against your own.** Every
seated player spins their own franchise each round (a 3-player table sees 3
spins in round 4). The spins are public; only what each player picked from
theirs is hidden. Sabotaging someone means knowing *their* franchise's history
at the slot. A finished roster is fourteen players from fourteen franchises.

**A seat's spin is public only once that seat's turn arrives.** A spin is
visible once its round is strictly in the past, or once it is the current round
and that seat's turn has been reached (`active_seat` gates it the way
`current_round` gates a round). Showing every spin up front hands out
information nobody should have yet. Nothing is redealt by revealing late.

**A franchise can be spun more than once in a game.** There is no no-repeat
rule.

```
  ROUND 4 of 14 · SLOT: WR1

  YOUR SPIN:  PITTSBURGH STEELERS

  Pick any WR who ever played for PIT, any year.
  ┌──────────────────────────────┐
  │  your pick (hidden)          │
  │  ??? · WR · PIT · ????       │
  └──────────────────────────────┘

  OTHER SPINS THIS ROUND (SEATS ALREADY UP):  Maya — NE
```

**The pick is hidden, identity and year both.** Nobody sees what you picked,
only that you picked something.

## Turns and guessing

**Turn order.** One seat drafts at a time, the rest sabotage them, then it
rotates, in fixed seat order every round. A round takes as many turns as there
are seated players.

**One shared clock per turn.** A turn is one `turn_deadline` (30 seconds). The
active seat may lock their pick any time within it, and every other seat may
lock exactly one guess or one explicit pass any time within it, including
before the pick exists, since the eligible pool (the active seat's spun
franchise) is public from the start of the turn. The turn ends early the moment
every seat has locked one action in. The clock is the backstop for an absent
seat.

**Pass is explicit.** Early completion needs to tell "hasn't acted yet" from
"chooses not to act", and silence cannot carry that. `submit_pass` is the
signal. Declining to guess is always legal.

**A guess is aimed at the turn.** `submit_guess` takes no target: it hits
whoever is on the clock. Each non-active seat has one guess per turn, so across
a round a guesser gets one shot at every other seat in turn.

**A guess made before the pick exists is held pending.** It is neither hit nor
miss until the pick lands (chosen, or substituted at the deadline). The whole
pending batch then resolves in one pass, in the order the guesses were made,
once the turn's action set is complete, so an earlier hit can change what a
later guess is checked against.

**Two guesses, two different weapons.**

- **Guess the player only.** If right, the pick keeps its player but is
  re-spun to a random *other* year of that player from the same team/position
  pool. If that player has only one season in the pool, the guess misses and
  the pick stands.
- **Guess the player and exact year.** If right, the *guesser* chooses any
  player and year from that team/position and assigns it into the victim's
  roster.

Cheap information (a name) buys chaos you don't control; expensive information
(a name and a year) buys a scalpel. If both paid out a free choice, the harder
guess would never be worth attempting below certainty.

**A turn takes at most two hits**, one respin and one exact assignment, in
either order. After that the pick is locked for the rest of the turn. Without
the cap, a pick could keep changing hands before its own window closes.

## X-Factor round

A wildcard upgrade, not a fifteenth slot. The final round spins a team as
normal but the pick may be any offensive skill player (QB/RB/WR/TE), any year,
through the same shared-clock turn flow.

When *that seat's* turn completes, the drafter alone decides: replace an
existing slot of the pick's own position (QB→QB, RB→RB1/RB2, WR→WR1-3, TE→TE),
bumping the old player out, or discard the pick. The decision happens before the
turn passes and cannot be guessed at or blocked. It is a chance to fix your
worst pick, not extra roster value, so a player happy with their picks should
discard.

## Value and results

**Approximate Value (AV), every slot, one scale.** QB/RB/WR/TE have fantasy
points but OL/DL/LB/CB/S/ST do not, and roster strength needs one number that
means the same everywhere. AV is blunter than PPR but avoids normalizing two
scales against each other.

**Record is a simulated season, not a formula.** Total roster AV sets a per-game
win probability and each player plays 17 simulated games, so a stronger roster
is favored, not guaranteed. Ties on record are therefore common and the
tiebreak treats "several teams tied" as normal. Against a roster of strength
`B`, strength `A` wins with probability `1 / (1 + exp(-((A - B) / 25)))`.

Games are played against a **fixed baseline** (Full: 93, from
`sabotage_draft_private.baseline_roster_strength`), not the table's own mean.
Grading against the table is self-cancelling: half the field finishes above
.500 however good or bad the drafts were. A fixed baseline lets a strong table
go 15-2 across the board. The match's board seed is reset before the simulation
so the season and bracket reproduce exactly.

**Tiebreak: single-elimination bracket of one-off games.** Pair the tied teams
at random (one random bye per odd count), simulate one game per pairing with the
same win model (using the paired players' actual strength, no baseline), winners
advance, repeat until one remains. A single game always has a winner, and byes
absorb odd counts at every layer.

## Table size

Two to four, the lobby limit. A round's length scales with player count (four
seats means four turns per round, fourteen rounds deep).

## Disconnects

Every resolution an absent player needs already exists for a present one:

- **Mid-pick, timer expires:** auto-resolve to a random player and year from
  that round's team/position. Not the best available, so disconnecting or
  stalling is never a viable strategy.
- **Mid-turn, no guess or pass:** silence is a legal choice. An absent seat can
  never complete a turn early, so the shared clock settles it.
- **Already picked, then disconnects:** the pick is locked server-side, and
  guesses against it resolve as if the player were present.

A disconnected player keeps their roster, stays on the scoreboard, gets a
simulated record, and can rejoin mid-match.

## Data

The pool needs full historical rosters by team and position (including
OL/DL/LB/CB/S/ST) and AV per player-season, which come from a different source
than the nflverse fantasy pipeline every other game reads. **Era floor: 2006.**
Team attribution follows who a player played for that year, including
mid-season trades and relocations. Decisions, constraints and the pipeline are
in [`data_scoping.md`](./data_scoping.md).

## Open

- Party point mapping (cross-cutting; see `docs/app.md`).
