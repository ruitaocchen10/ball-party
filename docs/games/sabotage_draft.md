# Sabotage draft

### Core idea

Fourteen rounds. Thirteen fill a fixed roster slot — QB, RB1, RB2, WR1-3, TE,
OL, DL, LB, CB, S, Special Teams — and the fourteenth is a wildcard shot at
upgrading one of them. Each round spins a random team; everyone picks any
player from that team's history at that slot's position, any year. Everyone
else can try to guess what you picked and wreck it if they're right. Once the
roster is set, its strength generates a simulated season record, and best
record wins. The skill is knowing team history deep enough to both make a
good pick and call another player's.

### Decided

**Round structure — one team spin per player per slot, picks made against your
own.** Every seated player spins their own franchise each round — a 3-player
table sees 3 spins in round 4, not 1 — but nothing about a spin is private:
the whole table can see which franchise every player is drafting from, only
not what they picked from it. That's still what makes guessing possible at
all — you can't call a shot on a search space you don't know — it's just that
the search space is now specific to whoever you're aiming at, rather than one
pool the whole table shares. Round 4 might spin the Steelers for you and the
Patriots for the player next to you; sabotaging them means knowing the
Patriots' WR1 history, not your own team's.

One consequence worth naming: a finished roster is fourteen players from
fourteen different franchises, not one team's real history. That's a feature,
not an accident — it's what keeps every round's pool fresh instead of the table
mentally exhausting one franchise's depth chart by round three.

**A round's spin is only public once the table actually reaches it — revised
from an earlier version of this design that dealt and revealed all fourteen
rounds' franchises up front.** The reasoning at the time was that nothing
about a spin is a secret, so there was no reason to withhold round 9's from a
table still on round 1. Playtesting showed that reasoning wrong: seeing every
future round's franchise from turn one hands out real information nobody is
supposed to have yet, including a player's own future spins, and quietly
kills the "you don't know your board yet" tension the rest of this design
leans on. What the earlier version got right stays true: the *current*
round's spin is visible to the whole table, cross-seat, the moment that round
opens — "Round 4 might spin the Steelers for you and the Patriots for the
player next to you" above still needs to hold, or a guess aimed at whoever's
turn hasn't come up yet has no search space to aim at. Only rounds strictly
ahead of the one in progress are now withheld, and they unlock the instant
the table reaches them — nothing is redealt or reshuffled by revealing late.

**A franchise can be spun more than once in a game.** No no-repeat rule across
rounds — e.g. the Patriots can come up for QB in round 1 and again for LB in
round 9. Simpler to reason about and to implement than tracking an exclusion
set across fourteen rounds, and a team turning up twice just means two
different slices of the same team's history get tested instead of one.

```
  ROUND 4 of 14 · SLOT: WR1

  YOUR SPIN:  PITTSBURGH STEELERS

  Pick any WR who ever played for PIT, any year.
  ┌──────────────────────────────┐
  │  your pick (hidden)          │
  │  ??? · WR · PIT · ????       │
  └──────────────────────────────┘

  OTHER SPINS THIS ROUND:  Maya — NE   ·   Sam — DAL
```

**The pick itself is hidden — identity and year both.** Nobody sees what you
picked, only that you picked something. That's the entire premise a guess is
priced against: a correct guess is real information recovered from nothing.

**Two guesses, two different weapons.** This is the mechanic worth protecting,
so it's worth being exact about what each one does and why they're priced so
differently:

- **Guess the player only.** If right, the pick is voided and instantly
  re-spun — a brand new random player *and* year from that same team/position,
  no choice involved for anyone. This is a coin flip you're forcing on your
  target: it might land on someone worse than what they had, might land on
  someone better. You're allowed to be right about *who* without knowing
  *when*, and the game's answer is to hand the outcome to chance rather than
  to you.
- **Guess the player and the exact year.** If right, the guesser — not the
  victim, not the dice — chooses any player and year from that same
  team/position and assigns it directly into the victim's roster. This is the
  actual "insert a terrible player" move: naming the exact card is a much
  harder guess, so getting it right hands you a deliberate, aimed act of
  sabotage instead of a random one.

The asymmetry is the whole design: cheap information (a name) buys you chaos
you don't control; expensive information (a name and a year) buys you a
scalpel. A version where both guess types handed the guesser a free choice
would make the harder guess pointless to ever attempt below certainty, since
partial credit already got you most of the value.

**Turn order — one seat drafts at a time, the rest sabotage them, then it
rotates.** Revised from an earlier simultaneous-picks version of this design:
seats go in fixed order (seat 1, seat 2, ...), the same order every round. A
round takes as many turns as there are seated players before the round
number itself advances — round 4 in a four-player game is four turns, not
one shared phase.

The earlier version had every seat pick and guess at once, on the reasoning
that nobody's pick is a contested resource the way an auction bid is, so
there was no obvious reason to force an order onto it. In practice that meant
every seat's hidden card sat exposed to every other seat's guess for the
whole window at the same time, with no way to tell "a guess aimed at me" from
"a guess aimed at whoever else is also picking this round" — sabotage lost
its target. Turn order fixes that directly: a guess is aimed at whoever
currently holds the turn, full stop, so there is no longer a target to
choose at all, only a decision to spend your one shot on this turn or hold it
for a later turn this round.

**One shared clock per turn — the pick and the sabotage happen at the same
time, not in sequence.** Revised again from an intermediate version of this
design that gave a turn two sequential windows: the active seat picks
against its own deadline, and only once that pick lands does a second,
separate window open for everyone else's guess. That is a needless wait —
nothing stops another seat from naming a guess the instant the turn starts,
since the eligible pool (the active seat's own spun franchise) is public
from the moment the turn opens, not from the moment the pick lands. A turn
is now one `turn_deadline`: the active seat may lock their pick any time
within it, and every other seat may lock in exactly one guess or one
explicit pass any time within that same window, including before the pick
exists.

**A guess made before the pick exists is held pending, not resolved blind.**
There is nothing yet to check an early guess against, so it sits recorded
but unresolved — neither a hit nor a miss — until the active seat's pick
actually lands, whether they chose it or the clock substituted one at the
deadline. Nothing resolves incrementally as guesses trickle in, either: the
turn's entire pending batch resolves in exactly one pass, in the order the
guesses were made, the moment the turn's whole action set is complete. An
earlier guess's hit can therefore change what a later pending guess is
actually being checked against — the same cascading behavior a
resolve-on-arrival guess always had, just settled all at once instead of
spread across however many separate submissions arrived first.

**Turn completion is symmetric: a pick and a guess are both just "this
seat's one action for the turn," and the turn ends the moment every seat
has locked one in.** The active seat's action is their pick; every other
seat's action is a guess *or an explicit pass* — deciding not to sabotage
this turn is as real and as locked-in a choice as guessing is. That symmetry
is what makes early completion possible at all: once the active seat has
picked and every other seat has either guessed or passed, the turn is over,
full stop, with no reason to sit out the rest of a clock nobody still needs.
The clock remains the backstop for whoever doesn't act at all — an absent
seat that neither picks nor guesses nor passes never completes the turn
early, so the shared deadline is still what eventually closes it, exactly
as an unanswered turn already worked before this.

**Pass is new surface, not an inferred default.** A guess stays optional —
naming a card you have no read on is not a real choice, and the design has
always treated declining to guess as legitimate. But early completion has
to be able to tell "hasn't acted yet" from "chooses not to act," and
silence cannot carry that distinction: a player who simply hasn't gotten to
their turn yet looks identical, over the wire, to one who never will.
`submit_pass` is the explicit signal that makes the difference visible,
the same shape the auction's own turn-based bidding already gives a player
who wants to end their turn without a bid.

**A guess is aimed at the turn, not at a player you pick.** Because only one
seat is ever guessable at once, `submit_guess` takes no target argument —
the target is whoever is currently on the clock. This is what makes the
sabotage economy legible: everyone watching a turn is looking at the same
hidden card, the same eligible pool (that seat's own spun franchise), and the
same clock.

**Guess economy — one guess per player, per turn, forced onto whoever is
active.** Everyone but the active seat gets exactly one guess to spend on
that seat's turn, and chooses only which of the two guess types to use — who
to aim it at is no longer a choice. Across a full round, that means a guesser
gets one shot at *every other* seat in turn, not one shot at a single target
of their choosing: in a 4-player game, each player watches three other turns
go by this round and may spend one guess on each. In a 3-player lobby where
round 4 spins the Patriots for the active player's QB slot, the other two
players each get one shot at that hidden pick — one might try "Tom Brady,
2017", the other "Drew Bledsoe, 2000", and if the actual pick was Drake Maye
2025, both miss and the pick stands.

This is what actually bounds the sabotage economy, rather than a rule bolted
on to stop spam: one guess per turn means a guesser who misses on someone's
turn cannot try again against that same pick later in the round, and a
guesser who wants to save their attention for a specific opponent still has
to sit through everyone else's turn to get there.

**A turn can still take at most two hits: one respin, one exact assignment.**
Even with one guess each, a popular target in a five- or six-player lobby can
draw guesses from every other player during their single turn, so the
per-turn cap still matters as a backstop. Without it, a respun pick is itself
guessable again by a later guesser in the same turn, and a pick that's
already been exactly assigned is *also* guessable by someone else's exact
guess, and a single turn could keep changing hands before its own window
closes. Two hits — one of each kind, in either order — is enough for the
drama and short enough to always terminate. Once a turn has taken its two
hits, the pick is locked for the rest of that turn regardless of who else
calls it or how many guesses they had left to spend on it.

**X-Factor round — a wildcard upgrade, not a fifteenth slot.** The final round
spins a team as normal, but the position isn't fixed to one slot: the pick is
any offensive skill player (QB/RB/WR/TE) from that team's history, any year.
It goes through the exact same one-shared-clock turn flow as every other
round — this is not a special case in the sabotage machinery, just a round
whose eligible position is wider than usual.

Once *that seat's own turn* — not the whole round — completes and the pick
is settled, that drafter alone makes one final call: slot the new player
into *any* one of their existing offensive skill slots (QB, RB1, RB2,
WR1-3, or TE), bumping whoever was there out of the roster entirely, or
discard the pick and leave the roster exactly as round 13 left it. This is
the one place a turn does something extra: the decision happens before the
turn passes to the next seat, not after every seat has taken theirs, so a
player can be deciding their own X-Factor while the rest of the table is
still waiting for their own turn to come around. That decision is the
drafter's alone and happens after their own turn has already closed — it
isn't itself something another player gets to guess at or block. A player
happy with all seven of their skill picks can, and often should, just
discard.

This is deliberately not a fifteenth roster slot. Giving it its own slot would
mean scoring fifteen players against fourteen everyone else has, and the whole
point is a *chance* to fix your worst pick, not guaranteed extra roster value.

**Value model — Approximate Value, every slot, the same scale.** QB/RB/WR/TE
have real fantasy points; OL/DL/LB/CB/S/Special Teams don't, and this game
needs one number that means the same thing across all fourteen. AV (Pro
Football Reference's cross-positional value metric) is the only established
answer to "how do I compare a Hall of Fame guard to a Hall of Fame receiver on
one scale." It's a blunter number than PPR — it won't separate two similar
receiver seasons as finely as points would — but the alternative is two
scales that need to be normalized against each other to sum into one roster
strength, which is a harder and shakier problem than accepting one blunter
scale everywhere.

**Record generation — simulated season, not a strength-to-record formula.**
Total roster AV sets a per-game win probability, and the record comes from
actually simulating a season game by game, the same way the auction and
Higher or Lower are both comfortable letting real variance decide outcomes
rather than pricing things deterministically. This means a stronger roster is
favored but not guaranteed a better record — an 11-6 team can lose to a 13-4
team's draft, which is the same shape of upset that makes real fantasy
seasons interesting to argue about. The direct cost of this choice: ties on
record are common, not rare, which is why the tiebreak below has to treat
"multiple teams tied" as the normal case.

The concrete model is logistic: against a roster of strength `B`, strength
`A` wins with probability `1 / (1 + exp(-((A - B) / 25)))`. Each player gets
17 independent season games against the table's mean strength; a tiebreak
uses the same formula with the paired player's actual strength. The match's
stored board seed is reset before this simulation, so the season and bracket
can be reproduced exactly.

**Tiebreak — single-elimination bracket of one-off simulated games.** Take
just the tied teams, pair them randomly (one random bye if the count is odd),
and simulate exactly one game per pairing using the same strength-to-win-
probability model as the season itself. A single simulated game always
produces exactly one winner, so this round can never itself need a
tiebreaker — there's no tie state one game can land in. Winners advance,
losers are out, repeat until one team remains.

This works for any number of tied teams because byes absorb odd counts at
every layer, the same way any single-elimination bracket does — there's no
special case to write for "what if it's odd" versus "what if it's even."

**Table size — two to six.** Turn order means a round's length now scales
directly with player count, the same shape as the auction's own turn-based
pacing concern: six seats means six turns before a round advances, fourteen
rounds deep. Six is a soft ceiling rather than a measured one — pushed
further, that many sequential pick-then-guess turns every round risks turning
into a long sit, but that's a pacing question for playtesting to tune (timer
lengths, possibly a shorter clock as the table gets bigger), not a structural
limit.

**Disconnects — reuse existing paths rather than invent an absent-player
case.** Every resolution a dropped player needs already exists for a present
one; the disconnect story is just routing through it automatically:

- **Mid-pick, timer expires with no choice made** — auto-resolve through the
  same random respin a successful name-only guess already triggers: a fresh
  random player and year from that round's team/position. Not the single
  highest-AV player available, on purpose — auto-picking the best option
  would make disconnecting (or stalling deliberately) a viable strategy, where
  a random outcome keeps it a real penalty for not being there, the same
  spirit as getting sniped.
- **Mid-turn, no guess or pass submitted** — declining to guess is already a
  legal choice for a present player (explicitly, via pass, or implicitly by
  never acting), so an absent one just defaults to silence. The one
  consequence worth naming: an absent seat's silence can never itself
  complete a turn early, since completion needs every seat's guess-or-pass
  accounted for — the shared clock is what eventually settles a turn stuck
  behind an absent player, same as it always was.
- **Already picked, then disconnects before the turn closes** — a guess
  against that pick, made while the turn is still open, resolves exactly as
  if they were present. The pick was already locked in server-side; being
  absent doesn't undo it, same as an auction bid that wins after the bidder
  drops.

Overall, a disconnected player keeps whatever roster they've built so far,
stays on the scoreboard, gets a record simulated for them like everyone else
at the end, and can rejoin mid-match — their first ping clears the absent
flag.

### Data

This is the open cost worth being honest about. Every other game in this app
draws from the same pool: nflverse weekly/season stats, which only exist for
QB/RB/WR/TE and only carry fantasy points as the value column. This game needs
two things nothing else here needs:

- **Full historical rosters by team and position**, including OL/DL/LB/CB/S/ST,
  going back far enough that a team's history at a slot is actually worth
  picking from — not just its skill-position fantasy pool.
- **AV per player-season**, which is a different source (Pro Football
  Reference) than the nflverse fantasy-points pipeline every other game reads
  from.

The auction cut DEF outright rather than stand up a second pipeline for one
slot out of six. This game needs that same kind of second pipeline for seven
slots out of fourteen, and unlike DEF it can't be cut — non-skill positions
are half the roster's rounds. That's a real scoping question before this game
is buildable, not a detail to settle during implementation.

Team attribution has the auction's same wrinkle, larger: a player's team in a
given season needs to reflect who they played for *that year* including
mid-season trades and franchise relocations, across every position, across
however many decades of history the pool ends up covering.

**Era floor — 2006, revised down from an earlier 1985 call.** Full scoping
(PFR page structure, franchise-code stability across relocations, access
constraints, scale, and a dedicated comparison of 1985 against other
candidate cutoffs) lives in
[`sabotage_draft_data_scoping.md`](./sabotage_draft_data_scoping.md). 1985 was
the first tentative call and is defensible on the merits scored there, but it
was walked back once the actual build cost became concrete: everything from
2006 through 2019 is available from nflverse's `nfldata/rosters.csv` for
free, with zero scraping against Pro Football Reference — the site the AV
data itself only exists on, sitting behind a Cloudflare JS challenge, rate-
limited to 20 requests/minute, under Terms of Use that are explicit and
restrictive about automated access. A 1985 floor meant scraping PFR directly
for 1985–2005 *and* 2020–present — roughly 780 team-season pages. A 2006
floor confines the live scrape to 2020–present alone — roughly 192 team-season
pages, about a quarter the exposure, in under 10 minutes at the rate limit
instead of 40+. The 2006 floor also happens to sit past AV's own 1994
tackle-counting seam, so unlike the 1985 window, every in-range season's
defensive AV is built from the same formula inputs.

The real cost, named plainly: this drops 21 years of history a 1985 floor
would have kept, including the specific deep-cut names the earlier scoping
called out as 1985's actual selling point — Marino's early prime, Walter
Payton's final seasons, Lawrence Taylor, Reggie White's debut, the '85 Bears
itself. That's a deliberate trade of recognizable history depth for a
substantially smaller, faster, lower-exposure build — made once the scraping
cost was concrete rather than estimated.

**Modes** — unresolved. Like the auction, this game's whole hook is other
people trying to wreck your draft, which argues against a solo mode existing
at all in the same way "an auction needs opponents" argues against one there.

### Open questions

- [x] **Data scope** — resolved as in scope, with a 2006 era floor (revised
      down from an earlier 1985 call once the live-scrape cost became
      concrete). See
      [`sabotage_draft_data_scoping.md`](./sabotage_draft_data_scoping.md) for
      the full scoping and the 1985-vs-2006 tradeoff. What's still open at the
      implementation level, not the design level — the position-vocabulary
      folding table and the mid-season-trade attribution rule — is described
      there rather than repeated here.
- [ ] **Party point mapping** — cross-cutting, still unanswered for the other
      three games too. See `app.md`.
