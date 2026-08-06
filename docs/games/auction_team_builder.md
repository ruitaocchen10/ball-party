# Auction team builder

### Core idea

Bid on mystery player-weeks to build a roster. Fantasy points are hidden during
bidding, but reveal upon selection. At the end; highest total wins. The
skill is knowing which player-weeks were secretly monsters and which were duds.

### Decided

**Card / lot reveal** — full identity, hidden points.

```
┌──────────────────────────────┐
│  LOT 4 of 20                 │
│                              │
│  SAQUON BARKLEY   RB         │
│  2018 · Week 12 · vs CHI     │
│                              │
│  FPTS: ? ? ?                 │
└──────────────────────────────┘
```

Name, position, year, and matchup are shown. The stat line and fantasy points
are hidden. Skill = recalling/estimating how that player performed in that era
and matchup.

**Budget** — $50 each.

**Roster** — 5 slots: QB, RB, WR, TE, FLEX.

DEF was cut. Team defense fantasy points aren't in the weekly player table —
they're derived from a different shape of data (sacks, INTs, fumble recoveries,
defensive TDs, safeties, plus a points-allowed tier bucketed from the final
score). That's a second ETL pipeline and a second scoring function to support
one slot out of six, and it's the slot nobody can actually reason about. The app
works fine without it, and most people don't care much about defense.

**Scoring format** — half-PPR. Sits between standard (which buries pass-catching
backs and TEs) and full PPR (which flattens the spread between stars and volume
guys). One-line config, but it feeds the tier ranks so it's upstream of the
pool build.

**Bidding** — turn-based ascending auction, one lot at a time:

- The right to open at $0 rotates each lot
- Play goes around the circle; each player either raises or passes
- **Passing drops you from that lot permanently**
- Player is assigned when everyone else has passed, or no one else can bid

Turn-based (not free-for-all) is deliberate — only one player can act at any
moment, so there are no race conditions, no simultaneous-submit reconciliation,
and no last-click-wins latency disputes.

**Pacing** — bidding sped up to keep the round tight:

- Hard 10s timer per action
- Fixed increment buttons (+$1 / +$5) so bidding is one tap
- Timeout = auto-pass

**Era range** — 2010-2024, flat. 15 seasons, all inside plausible memory for
anyone who's followed fantasy in the last decade. Highest floor — near-zero dead
lots. Widen after playtesting if it starts feeling samey.

**Lot visibility** — blind. Current lot only, no lookahead, no board. Every
reveal stays a genuine surprise.

- Tradeoff accepted: without comparative context you can't fully price a card,
  so bidding leans on gut and name recognition more than on relative value.
- Optional cheap mitigation: show counts remaining by position in the header
  (`Lot 4 of 20 · QB: 2 left`). Leaks no card identities, keeps every reveal a
  surprise, but makes "is this my last shot at a QB" knowable — which is what
  gives the budget teeth.

**Score visibility** — fully public scoreboard. Points reveal on selection, and
everyone's running total plus remaining budget is always on screen.

- The rubber-band effect is a feature: whoever is behind has a reason to spend
  hard, whoever is ahead sits on their budget. Mario Party does this on purpose.
- Comebacks stay live because of the same variance that makes the game noisy.
  Single-week skill-position scores run ~0-35 with a standard deviation around
  8-10, so with 4 lots left the realistic swing between two players is 30-40
  points — a deficit that feels fatal usually isn't.
- Spreading the payoff across the round matters more now that bidding is blind.

**Lot scheduling** — get a list of players up front, then randomize how they come
out. The position counts need to be exact, but that's provably safe in ~15 lines:

```
4 players × [QB, RB, WR, TE]  →  4 QB, 4 RB, 4 WR, 4 TE   (16 base)
4 players × [FLEX]            →  4 more from {RB, WR, TE}  (4 flex)
```

Deal the 16 base lots shuffled, then the 4 flex lots last. While base lots run,
the number of QB lots remaining always exactly equals the number of players
still missing a QB — so every lot always has at least one eligible bidder and
nobody can be stranded. The final 4 flex lots are ones everyone is eligible for
by definition. The flex round at the end becomes a natural climax where all the
leftover budget collides.

**Player pool** — quota-based, tiered on season positional finish:

```
20 LOTS
  7 · STAR    pos rank 1-5
  8 · SOLID   pos rank 6-24
  5 · DEEP    pos rank 25-40
```

The deep-cut tier is doing real work — it's what gives the star cards something
to be expensive _relative to_. If every card is a star, every card is expensive,
the price spread collapses, and the game becomes pure noise.

Tiering on season finish (rather than Pro Bowl / All-Pro) because it's free in
the nflverse data, needs no second source and no name join, and measures the
exact thing players are being asked to reason about. Not a one-way door — tier
is just a column, so accolades can be swapped in later without touching game
logic.

### Data

- **nflverse** — weekly player stats, free, no API key, back to **2010**
- Carries name / position / team / opponent and precomputed standard + PPR
  fantasy points
- One dataset, zero joins

**Modes** — arcade ✓, party ✓, individual ✗.

An auction needs opponents, so there's no solo version. In arcade you make a
lobby and play just this game; a winner is declared at the end and nothing
carries over. In party mode the same game runs and the result feeds the meta
scoreboard. The game itself is identical in both — only the wrapper differs.

### Open questions

- [ ] **Party point mapping** — how does auction placement convert to party
      points? Cross-cutting; see `app.md`.
- [ ] **Tie-breaks and disconnects**
