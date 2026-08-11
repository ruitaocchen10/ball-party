# 2v2 Wavelength

### Core idea

Four players are randomly paired into two teams. Each player secretly sees a
hidden target on a spectrum and writes a one-shot clue aimed at it. Their
partner then has to place that clue back on the spectrum. Score is closeness.
The skill is modelling how one specific person carves up a fuzzy scale.

### Decided

**Game model** — true Wavelength. The app owns a hidden target; the psychic
sees it and writes a clue; the partner guesses the position.

The board is a semicircular dial. The target is five wedges scoring
**2 / 3 / 4 / 3 / 2**, symmetric around a bullseye, sitting at a random spot on
the arc. The guessing team rotates a needle that pivots from the centre.

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

The physical game hides the target behind a rotating screen that only the
psychic lifts. Our RLS policy on the target column is the direct analogue, and
it has to do the same job: everyone sees the arc and the clue, exactly one
person ever sees where the wedges are.

Not combinatorial. Drawing a random subject and a random axis independently
sounds like leverage — 40 subjects × 15 axes = 600 cards — but most pairings are
nonsense (`"A running back" × Cold/Hot`), so it needs a hand-authored
compatibility matrix, which is more work than writing whole cards. And you can't
taste-test 600 generated cards.

**Prompt bank** — hand-authored, ours. Wavelength's published decks are
copyrighted, the prompts _are_ the game so taste beats sourcing, and the volume
is a text file rather than a data pipeline. Expected workflow is AI drafts a
large list, human curates down — generation is cheap, taste is the scarce input.

**Round structure** — 4 players × 2 cards = 8 rounds. Fill phase runs in
parallel (everyone writes both clues at once, timed), then guessing runs
sequentially, alternating teams.

**No catch mechanic.** Real Wavelength has the opposing team bet left/right of
the guess for a bonus point, specifically to keep them engaged. We're skipping
it. Idle players watch the action.

**Hidden target enforcement** — the target lives in a column that RLS exposes to
the psychic alone. This is the single strongest reason the stack fits: the
alternative is hand-rolling per-player view filtering on every broadcast,
forever, where getting it wrong once silently ruins games.

### Open questions

- [ ] **Scoring** — copy the physical 2/3/4/3/2 wedges, or use continuous
      distance? Bands are more readable, more forgiving, and give a discrete
      "we got a 4!" moment; continuous is more precise but harder to feel good
      about and has no natural celebration point.
- [ ] **Wedge widths** — the physical board fixes them. Do we keep them fixed
      all game, or narrow them in later rounds to raise the stakes?
- [ ] **Clue validation** — what stops `"62 percent"`? Needs at minimum a word
      limit and a digit ban, and neither is enforceable against a determined
      cheater. May just be a social rule.
- [ ] **Timer durations** — fill phase and guess phase, both unset.
- [ ] **Team pairing** — random is decided, but does it reshuffle between games
      in a session or hold?
- [ ] **Does the guessing team see the card before the clue?** Affects whether
      they can pre-think the scale.
- [ ] **Repeat avoidance** — is a `seen_cards` table worth it at MVP, given the
      target re-randomizes?
- [x] **Accounts or not** — decided: guests join by room code with just a name,
      hosting needs an account. See ball-party#7.
- [ ] **Party point mapping** — how does round score convert to party points?
- [ ] **Arcade mode** — this needs a partner to read. Bots, or a different
      single-player format?
- [ ] **Tie-breaks and disconnects.**
