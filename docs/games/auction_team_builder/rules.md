# Auction team builder

Players bid on mystery fantasy lots to fill a roster. Each lot shows a player's
full identity but hides his fantasy points until it sells. The skill is
recalling or estimating how that player performed in that era and matchup, and
pricing it against a limited budget. Four players is the designed table. Two or
three deal an honest board but exist for testing.

Implemented in the `auction` / `auction_private` schemas. Arcade only (see
`docs/app.md`); the game has no solo mode, because an auction needs opponents.

## The lot

Name, position, year, week and opponent are shown. The stat line and points are
hidden until the lot resolves. Lots can be a single week or a full season
total (the host picks). Scoring is full PPR. Matchup team codes are mapped back
to what the team was called at the time (nflverse normalises to the modern
franchise).

Dud weeks stay in: a 0.0 is part of what makes a bid a bid.

Undealt players are never revealed. The board records settled lots only.

## Format

The host picks a roster preset and an era window before dealing. The match
stores the resolved counts and purse, so a finished board stays readable if a
preset is retuned later.

| Preset | QB/RB/WR/TE/FLEX | Slots | Lots at four players | Purse |
| --- | --- | ---: | ---: | ---: |
| Standard | 1/1/1/1/1 | 5 | 20 | $25 |
| Full | 1/2/2/1/1 | 7 | 28 | $35 |
| Deep | 2/2/3/1/2 | 10 | 40 | $50 |

A player can win up to the preset's count at each position, never more. There is
no DEF slot: team defense points come from a different data shape.

**Era.** The pool is 2010 to the latest completed season, and the host picks a
window inside it (default: all of it). The window must span at least four
seasons: shorter windows can fail to deal a Deep board (`pool_exhausted`, which
remains as a backstop). Both bounds come from the pool, so nothing hardcodes a
year.

## Bidding

Turn-based ascending auction, one lot at a time:

- The right to open at $0 rotates each lot to the next *eligible* player.
  Eligible means having an open roster slot the lot can fill.
- Play goes around the circle. Each player raises or passes.
- **Passing drops you from that lot permanently.**
- The lot goes to the high bidder when everyone else has passed or no one else
  can bid. Opening is $0, so an eligible player can always take a lot free and
  budget never strands anyone.
- The match ends as soon as every roster is full, not only when the deck runs
  out.

Turn-based on purpose: one actor at a time means no simultaneous-submit
reconciliation or last-click-wins disputes (the Seal token is the one
deliberate exception, below).

**Disconnects** fall out of the pacing: a dropped player auto-passes every
remaining lot, keeps their budget and wins, and a dropped high bidder still wins
that lot.

### Pacing

- 20s per action, 5s preview before each lot, 5s sold acknowledgement after.
- Fixed +$1 / +$5 buttons plus an exact custom bid.
- Timeout is auto-pass, through the same code path as a manual pass (two paths
  resolving a lot would drift).

### Who fires the timeout

Never only the player on the clock; closing the tab is exactly the case the
timer exists for. The deadline is a `turn_deadline` column and expiry is an RPC
any participant may call. It locks the match, re-checks `now() >= turn_deadline`
in server time, and either applies the auto-pass or does nothing, so duplicate
calls are harmless.

- Clients ask repeatedly, not once, and re-ask after a no-op. The server decides
  what is true.
- The visible countdown ends at 19.5s against the 20s deadline so a last-moment
  bid survives latency. Non-acting clients fire with 300-800ms jitter so the
  acting player gets first crack.
- A 30s `pg_cron` sweep is the janitor for matches nobody is watching. It gives
  a live turn a minute of grace and a preview or sold acknowledgement two
  seconds, since those hold no decision.
- Server `now()` ships with match state so clients can offset their clocks. The
  screen re-reads in full on a stale deadline, a tab returning to the
  foreground, and a channel rejoin: realtime is the fast path, not the only one.

## Lot scheduling and flex

FLEX can be filled any time a player's natural slots for it are done. Lots are
shuffled across the board, and eligibility is decided live:

- Natural slot open: always eligible.
- Natural slot full, FLEX open: eligible only if enough of that position remains
  undealt to cover every *other* player's remaining natural need, counted in
  slot units (a player missing two RB slots needs two units).

**Deal invariant.** QB is exactly N lots (never flex-eligible). RB/WR/TE get N
of each plus at least `N * flex_slots` of slack, split at random across the
three, with a floor of two spares per position. Less slack strands a player in
every simulated trial; at least that much never does. An unusable spare is
skipped while still hidden, and a spare the table never reaches costs nothing
because the match ends when rosters fill. Totals at four players: Standard 20+2,
Full 28+2, Deep 40+0.

## Pool and tiers

The pool is nflverse weekly player stats, filtered to a tier mix and dealt
reproducibly from a seed. Lots are tiered 7 star : 8 solid : 5 deep per 20 lots,
spread across 5N lots by largest remainder, ties to star (N=3: 5/6/4, N=2:
4/4/2). The deep tier gives stars something to be expensive relative to.

Tier is a per-season positional finish, never shown to players, with
per-position bands because positions are not equally deep. The bands live in
config and are tuned by dealing sample boards.

```
          STAR      SOLID       DEEP
  QB      1-5       6-18       19-32
  RB      1-5       6-24       25-45
  WR      1-5       6-30       31-60
  TE      1-5       6-18       19-32
```

Narrowing the era window keeps the 7:8:5 mix (the stars of that window), at the
cost of repetition: 2020-2025 holds 73 distinct star players against 159 for the
full era.

## Score visibility

The scoreboard is public. Points reveal on sale and everyone's total and
remaining budget are always on screen. The rubber-band effect is intended:
whoever trails has a reason to spend, and single-week variance (sd about 8-10
points) keeps comebacks live.

## Tokens

Each match carries a small per-player budget (0-3, `token_count`) of single-use
abilities, each usable once per player:

- **Pass.** Normally a lot nobody else bids on resolves to the last live bidder
  for $0 without asking them. Passing spends a token to decline that lot. A
  decline redraws one more player of the same position onto the end of the
  deck, so supply is conserved and the deal invariant above still holds. A
  timeout on that seat takes the free $0 claim instead and never burns a token.
- **Scout.** Spend a token on the current lot to see a coarse tier (rough /
  solid / great) privately, before it resolves. Week matches use week-relative
  PPR thresholds; season matches use the position-relative percentile across
  the season pool (bottom third rough, top quarter great).
- **Seal.** Before anyone has bid, a live player may seal the current lot (only
  when two or more players are live on it). The match enters a `sealed` phase:
  every live player gets one private first-price bid on a shared clock. The
  last submitter resolves it, and a missed deadline counts as a $0 bid.

Scout hints and sealed amounts are visible only to their owner, enforced by RLS
on tables that sit in the realtime publication, not by the UI.

## Open

- Tie-breaks when two players finish on the same total.
