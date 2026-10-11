# 2v2 Wavelength

Start it from a lobby with two players for co-op or four for versus. Arcade
only (see `docs/app.md`); there is no solo mode, since the game needs a partner
to read a clue.

### Core idea

Players take turns as the psychic. The psychic secretly sees a hidden target on
a spectrum and writes a one-shot clue aimed at it. A partner then has to place
that clue back on the spectrum. Score is closeness. The skill is modelling how
one specific person carves up a fuzzy scale.

There are two modes, picked by the host in the lobby:

- **2v2** — four players, randomly paired into two teams that compete.
- **Co-op** — two players on one team, trying to reach a target score in a fixed
  number of rounds.

### Decided — both modes

**Game model** — true Wavelength. The app owns a hidden target; the psychic
sees it and writes a clue; the partner guesses the position.

The board is a semicircular dial. The target is five wedges scoring
**2 / 3 / 4 / 3 / 2**, symmetric around a bullseye, sitting at a random spot on
the arc. The guessing player rotates a needle that pivots from the centre.

```
   ROUND 3 of 8 · KAYLA is the psychic

                        2    3    4    3    2
                         ╲    ╲   │   ╱    ╱
           ╭──────────────╲────╲──│──╱────╱─────────────╮
        ╭──╯      ╲        ╲    ╲ │ ╱    ╱               ╰──╮
      ╭─╯          ╲        ╲    ╲│╱    ╱                    ╰─╮
     │              ╲        ╲    │    ╱                        │
     │     needle    ╲        ╲   │   ╱                         │
     ╰────────────────────────●─────────────────────────────────╯
       Less likely                                   More likely

              A player you'd want to party with
                        CLUE:  "Gronk"
```

The wedges are drawn centred here only for legibility — the target lands
anywhere on the arc. The needle above is sitting in a left `3`.

**Scoring** — bands, not continuous distance. Max 4 per guess. Bands give a
discrete "we got a 4!" moment and a clean target for co-op.

**Wedge width** — fixed for the whole game (no narrowing in later rounds), about
4% of the arc per wedge (20% total scoring zone). A single config constant,
kept beside the star thresholds below because the two move together.

**Hidden target enforcement** — the target lives in a column that RLS exposes to
the psychic alone. Everyone sees the arc and the clue; exactly one person ever
sees where the wedges are. The target is revealed to everyone when a guess
locks.

**Fill phase** — parallel and up front. Every player writes all of their clues
at once, timed, then guessing runs sequentially, alternating players (and teams,
in 2v2). A guesser sees the spectrum only when it is their turn to guess; during
the fill phase each player sees only their own cards.

**Needle visibility** — the guesser's needle is live for everyone, so spectators
have something to watch. Updates are throttled to a few per second. The target is
never part of what is broadcast.

**Clue limits** — enforced server-side: 1 to 8 words, at most 100 characters, no
digits. Spelled-out numbers ("sixty-two") are not enforceable and stay a social
rule. The limits are a single constant; tighten them if clues turn into
descriptions of the position.

**Timers**

- Fill phase: one clock for the whole phase, 90 seconds per clue the player has
  to write (Short 180s, Medium 270s, Long 360s; 2v2 uses two clues per player,
  so 180s).
- Guess phase: 60 seconds per guess.

**Timeouts**

- A clue that isn't written in time skips that round for 0 points.
- A guess that isn't confirmed in time auto-locks the needle where it currently
  sits.

**Disconnects** — same model as Sabotage Draft. A disconnected seat stays in the
match, flagged absent, and can rejoin (its next ping clears the flag). Missed
actions resolve through the timeout rules above rather than a separate
absent-player path. There is no cap on absence in co-op: an absent partner just
produces skipped and auto-locked rounds until they return or the match finishes.

**Prompt bank** — hand-authored whole cards (two endpoints each). Wavelength's
published decks are copyrighted, and subject and axis cannot be combined
randomly (`"A running back" × Cold/Hot` is nonsense).

- The deck is 68 cards in `wavelength_private.deck`, seeded by migration
  `0161` and synced to `cards.md` by `0201`. `card_id` is stable; a match copies the labels it was dealt, so editing
  the deck never rewrites a finished match.
- **Every card is football-related**, with no `nfl`/`general` tag. A good card is
  a spectrum where reasonable people place the same clue at different spots.
- No repeats within a match (draw without replacement). Nothing is tracked
  across matches at MVP; the target re-randomizes anyway.

**No catch mechanic.** Real Wavelength has the opposing team bet left/right of
the guess for a bonus point. We skip it; idle players watch the live needle.

**Accounts** — multiplayer requires a real account (see `docs/app.md`).

**Lobby** — the host picks Co-op or 2v2 explicitly. Start is enabled only when
the player count matches the mode (2 for co-op, 4 for 2v2); three players can't
start. The catalog lists the game as "2 or 4 players".

**Result** — Wavelength records a structured result (final score, outcome
win/lose or placement, bullseye count, preset), so a future party-points mapping
can be applied without touching the game.

### Decided — 2v2

- Four players, randomly paired. Teams **reshuffle every game**; there is no
  attempt to avoid repeating the previous pairing.
- 4 players × 2 cards = 8 rounds.
- **Ties** — the team with more bullseyes (4-point guesses) wins. If that is
  also tied, play sudden-death rounds, each with a fresh card and the same rules
  as a regular round, until one team leads.

### Decided — co-op

Two players are one team. They alternate as psychic, and each player psychs N
times. All rounds are always played — there is no early win or early loss — and
the team wins if the final score is at or above the target.

| Preset | Rounds (N per player) | Target | Max | ★★ | ★★★ |
| ------ | --------------------- | ------ | --- | -- | --- |
| Short  | 4 (2 each)            | 8      | 16  | 12 | 15  |
| Medium | 6 (3 each)            | 12     | 24  | 18 | 22  |
| Long   | 8 (4 each)            | 20     | 32  | 24 | 29  |

The host picks the preset in the lobby. Meeting the target earns one star; the
★★ and ★★★ columns are the score thresholds for further stars. The ★★★ line is
near-perfect bullseyes and is meant to be aspirational. Thresholds live in config
next to the wedge width, so both can be retuned after playtesting.

The result screen shows the score against the max, a bullseye count, and the star
tier.

### Open

- Wedge width and star thresholds are starting values; tune against how real
  games score.
- Sudden-death rounds need their own fill and guess phase; their timer lengths
  are not decided.
