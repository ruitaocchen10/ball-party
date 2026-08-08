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

**Scoring format** — full PPR. Every catch is a point, which is the format most
people have actually played and therefore the one they can price from memory.
It does flatten the spread between stars and volume guys, and that's accepted:
the spread this game trades on is between a good week and a bad one, not between
two players' season-long roles. One-line config, but it feeds the tier ranks so
it's upstream of the pool build.

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

**Era range** — 2010-2025, flat. 16 seasons, all inside plausible memory for
anyone who's followed fantasy in the last decade. Recall is the floor that
matters here, not scoring. The upper bound is the most recent completed season
and moves with it. Widen the lower bound after playtesting if it starts feeling
samey.

**Dud weeks** — kept, not filtered out. A player who took four snaps and left
injured is still a lot, and his 0.0 still counts. The live possibility of a zero
is part of what makes a bid a bid, and allowing it costs nothing to build: 16%
of regular-season skill weeks are already at or below 0.0 PPR. The tradeoff is
that a few lots end up unguessable rather than merely hard — accepted, since the
alternative is a snap-count filter that needs a second dataset and only reaches
back to 2012.

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
  7 · STAR
  8 · SOLID
  5 · DEEP
```

The deep-cut tier is doing real work — it's what gives the star cards something
to be expensive _relative to_. If every card is a star, every card is expensive,
the price spread collapses, and the game becomes pure noise.

**Bands are per position, because positions aren't equally deep.** One rank
range can't mean the same thing at QB and at WR — in 2023 there were 81 QBs with
a season total and 224 WRs, so rank 25-40 is a backup at one and a fantasy
starter at the other. Uniform bands would leave the WR pool with no deep cuts in
it at all, which is precisely the collapse the tier exists to prevent.

```
          STAR      SOLID       DEEP
  QB      1-5       6-18       19-32
  RB      1-5       6-24       25-45
  WR      1-5       6-30       31-60
  TE      1-5       6-18       19-32
```

Starting values rather than settled ones. They live in config and get tuned by
dealing sample boards and reading the names — see
[issue #1](https://github.com/ruitaocchen10/ball-party/issues/1).

Tiering on season finish (rather than Pro Bowl / All-Pro) because it's free in
the nflverse data, needs no second source and no name join, and measures the
exact thing players are being asked to reason about. Not a one-way door — tier
is just a column, so accolades can be swapped in later without touching game
logic.

Rank is on season *total*, so a star who missed six games ranks like a mediocre
full-season one — 2023 Joe Burrow lands in DEEP. Left that way on purpose: tier
is never shown to anyone, so it only shapes the mix, and a big name carrying a
quiet tier is a perfectly good card. Points-per-game is there if tuning wants
it.

### Data

- **nflverse** — weekly player stats, free, no API key, back to **2010**
- Carries name / position / team / opponent and precomputed standard + PPR
  fantasy points
- One dataset, zero joins

Team codes are the one wrinkle: nflverse normalises them to the modern
franchise, so a 2015 game against San Diego comes back as `LAC`. The matchup is
one of four recall cues on the card, so they get mapped back to what they were
called at the time. Shape, tiering, and load live in
[issue #1](https://github.com/ruitaocchen10/ball-party/issues/1).

**Modes** — arcade ✓, party ✓, individual ✗.

An auction needs opponents, so there's no solo version. In arcade you make a
lobby and play just this game; a winner is declared at the end and nothing
carries over. In party mode the same game runs and the result feeds the meta
scoreboard. The game itself is identical in both — only the wrapper differs.

### Open questions

- [ ] **Party point mapping** — how does auction placement convert to party
      points? Cross-cutting; see `app.md`.
- [ ] **Tie-breaks and disconnects**
