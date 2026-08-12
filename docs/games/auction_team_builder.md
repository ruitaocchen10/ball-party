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

**Roster preset and budget** — the host chooses one before dealing. The match
stores these resolved counts and purse, so a completed board remains readable if
a preset is later retuned.

| Preset | QB/RB/WR/TE/FLEX | Slots | Lots at four players | Purse | Est. length |
| --- | --- | ---: | ---: | ---: | --- |
| Standard | 1/1/1/1/1 | 5 | 20 | $25 | 10–14 min |
| Full | 1/2/2/1/1 | 7 | 28 | $35 | 15–20 min |
| Deep | 2/2/3/1/2 | 10 | 40 | $50 | 20–28 min |

The same five dollars per slot keeps the bid increments meaningful across
presets. Repeated positions are independently visible roster slots; a player can
win up to that preset's count, never more.

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

- The right to open at $0 rotates each lot, to the next *eligible* player
- Eligibility is having an open roster slot the lot can fill — see lot
  scheduling, which depends on it
- Play goes around the circle; each player either raises or passes
- **Passing drops you from that lot permanently**
- Player is assigned when everyone else has passed, or no one else can bid

Turn-based (not free-for-all) is deliberate — only one player can act at any
moment, so there are no race conditions, no simultaneous-submit reconciliation,
and no last-click-wins latency disputes.

**Pacing** — retuned after playtesting:

- Hard 20s timer per action
- A 5s preview before every lot, and a 5s sold acknowledgement after it
- Fixed increment buttons (+$1 / +$5) so bidding is one tap, plus an exact
  custom bid for anything else
- Timeout = auto-pass

These went up, not down. The first playtest read as slow, but the measurements
said otherwise: a lot nobody bid on resolved in 5-6s and a lot that ran its full
turn took 16s, both correct. What actually hurt were three lots in the same game
taking 81s, 127s and 271s — one of them with no player actions at all, which no
turn timer explains. That was a stalled phase transition, not pacing. With the
stalls fixed, ten seconds turned out to be too short to price a lot you have
never seen, and 1.2s too short to read the number you just paid for.

**Who fires the timeout.** Not the player on the clock — that is the one client
that cannot be trusted with it, since closing the tab is precisely the case the
timer exists for. So the deadline is a `turn_deadline` column on the match, and
expiry is an RPC any participant may call: it locks the match, re-checks
`now() >= turn_deadline` in server time, and either applies the auto-pass or
does nothing.

Client clocks decide when to ask, never what is true. Idempotency is free — the
first caller advances the turn and sets the next deadline in the future, so
every other caller no-ops. A turn hangs only if all four clients are gone, and
a 30s `pg_cron` sweep clears those so an abandoned match doesn't sit `playing`
forever. The sweep is a janitor, not the mechanism: on a match anyone is
watching, it never fires first.

**Clients ask repeatedly, not once.** The first version fired one expiry request
per state and latched, so a single no-op meant nobody ever asked again — and for
the timer-only phases it fired at exactly the deadline with no slack, handing any
client whose clock ran a millisecond fast a guaranteed no-op. That is what turned
a 6-second lot into a 127-second one. Asking again costs nothing, because the
server re-checks under the match lock and does nothing if it disagrees.

**The janitor's grace is split by phase.** A minute of grace on a live turn
protects a real person whose network hiccupped; cutting their decision short
because a packet was late is the failure worth paying a minute to avoid. A
preview or a sold acknowledgement holds no decision and no person — it is a
timer that has already run out — so those are swept after two seconds.

Three details that are easy to get wrong:

- **Auto-pass reuses the pass path.** Timeout sets a flag for the UI and runs
  identical code. Two paths that both resolve a lot will drift.
- **The visible countdown ends early** — clients count to 19.5s against a real
  20s deadline, so a bid sent at the last moment isn't killed by network
  latency. The slack sits behind the clock rather than in front of it, which
  keeps zero meaning zero.
- **Non-acting clients fire with jitter** (+300-800ms) in every phase, so the
  player on the clock gets first crack, four clients don't stampede, and a
  slightly fast clock doesn't spend its attempt on a certain no-op.
- **The screen reconciles rather than trusting realtime.** Payloads are applied
  as they arrive, but a deadline that stays past, a tab returning to the
  foreground, and a channel rejoin each trigger a full re-read. Realtime is the
  fast path, not the only one: a single dropped payload used to leave the screen
  permanently wrong with nothing to say so.

Server `now()` ships alongside match state, so a client can offset its own
clock rather than trust it.

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

**Table size** — four players. The board is dealt for N and the no-stranding
proof holds for any N, but four is the game: it is what the budget, the twenty
lots and the tier quota were tuned against.

N exists for one reason. A game hardcoded to four cannot be tested without four
signed-in browsers, which puts every bidding, timer and reveal bug behind a
four-window setup for the whole build. Two and three players deal a real board
and play an honest game — but they are a development affordance, not a designed
mode, and nothing in the UI offers them.

**Lot scheduling** — get a list of players up front, then randomize how they come
out. The position counts need to be exact, but that's provably safe in ~15 lines:

```
N players × [QB, RB, WR, TE]  →  N of each                 (4N base)
N players × [FLEX]            →  N more from {RB, WR, TE}  (N flex)
```

Deal every base position count × N shuffled, then flex count × N flex lots last.
At a four-player table, Standard is 16 + 4 = 20, Full is 24 + 4 = 28, and Deep
is 32 + 8 = 40.

**A base lot may only be bid on by players whose natural slot is still open.**
FLEX is eligible during the flex round and nowhere else. That rule is what makes
the schedule safe: the number of RB lots remaining then always exactly equals
the number of players still missing an RB, so every lot has at least one
eligible bidder and nobody can be stranded.

Without it the proof holds for QB alone. A quarterback fits only the QB slot, so
QB is safe however FLEX behaves — but an RB lot could be taken into somebody's
FLEX, and then the RB lots run out while a player still needs one. Restricting
FLEX to the flex round costs nothing and is what the scheduling argument was
always quietly assuming.

The final N flex lots are ones everyone is eligible for by definition, so the
flex round stays the natural climax where all the leftover budget collides.

Budget cannot strand anyone either: opening is at $0, so an eligible player can
always take a lot for free. Eligibility is the only thing a roster slot can turn
on.

**Player pool** — quota-based, tiered on season positional finish:

```
20 LOTS
  7 · STAR
  8 · SOLID
  5 · DEEP
```

Below a full table the same 7:8:5 is spread across 5N lots by largest remainder,
ties to star: N=3 gives 5/6/4, N=2 gives 4/4/2. Deterministic, so a board is
reproducible from its seed.

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
- [ ] **Tie-breaks** — two players finishing on the same total.

**Disconnects** fall out of the pacing rules above rather than needing their own
answer. A player who drops auto-passes every remaining lot, keeps their budget
and whatever they already won, and the round runs on at full speed without them.
A player who drops while holding the high bid still wins that lot — they
committed, and being absent doesn't undo it.
