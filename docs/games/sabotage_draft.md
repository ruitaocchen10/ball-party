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

**Round structure — one shared team spin per slot, picks made against it.** The
team spin is a single table-wide event, not a private one. Everyone at the
table is drafting from the same team's history for that slot, which is what
makes guessing possible at all — you can't call a shot on a search space you
don't know. If team spins were private, sabotage would be a guess against pure
noise, and the whole second half of the game disappears.

One consequence worth naming: a finished roster is fourteen players from
fourteen different franchises, not one team's real history. That's a feature,
not an accident — it's what keeps every round's pool fresh instead of the table
mentally exhausting one franchise's depth chart by round three.

**A franchise can be spun more than once in a game.** No no-repeat rule across
rounds — e.g. the Patriots can come up for QB in round 1 and again for LB in
round 9. Simpler to reason about and to implement than tracking an exclusion
set across fourteen rounds, and a team turning up twice just means two
different slices of the same team's history get tested instead of one.

```
  ROUND 4 of 14 · SLOT: WR1

  TEAM SPIN:  PITTSBURGH STEELERS

  Pick any WR who ever played for PIT, any year.
  ┌──────────────────────────────┐
  │  your pick (hidden)          │
  │  ??? · WR · PIT · ????       │
  └──────────────────────────────┘
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

**Guess economy — one guess per player, per round, aimed at a single target.**
Everyone who isn't the one being guessed at gets exactly one guess to spend
that round, and chooses both who to aim it at and which of the two guess
types to use. In a 3-player lobby where round 4 spins the Patriots for QB, the
other two players each get one shot at the third player's hidden pick — one
might try "Tom Brady, 2017", the other "Drew Bledsoe, 2000", and if the actual
pick was Drake Maye 2025, both miss and the pick stands.

This is what actually bounds the sabotage economy, rather than a rule bolted
on to stop spam: with only one guess a round, going after any one target means
not going after anyone else, so in a table bigger than three the real decision
is *who* is worth your one shot this round, not whether to take it.

**A slot can still take at most two hits in a round: one respin, one exact
assignment.** Even with one guess each, a popular target in a five- or
six-player lobby can draw guesses from every other player in the same round,
so the per-slot cap still matters as a backstop. Without it, a respun slot is
itself guessable again, and a slot that's already been exactly assigned is
*also* guessable by someone else's exact guess, and a single crowded slot
could keep changing hands all round. Two hits — one of each kind, in either
order — is enough for the drama and short enough to always terminate. Once a
slot has taken its two hits, it's locked for the round regardless of who else
calls it or how many guesses they had left to spend elsewhere.

**Picks lock simultaneously, then one shared guessing window opens for
everyone.** Same shape as Higher or Lower's simultaneous calls: there's no
turn order to a pick, since nobody's choice is a contested resource the way an
auction bid is. The guessing window is free-for-all rather than turn-based —
anyone can call a shot on anyone, in any order, for as long as the window is
open — because sabotage is explicitly a race: the first correct guess on a
slot is the one that counts, and turn order would just be an arbitrary
handicap on who gets to try first.

**X-Factor round — a wildcard upgrade, not a fifteenth slot.** The final round
spins a team as normal, but the position isn't fixed to one slot: the pick is
any offensive skill player (QB/RB/WR/TE) from that team's history, any year.
It goes through the exact same hidden-pick-then-guess-window flow as every
other round — this is not a special case in the sabotage machinery, just a
round whose eligible position is wider than usual.

Once that round's guess window closes and the pick is settled, the drafter
makes one final call: slot the new player into *any* one of their existing
offensive skill slots (QB, RB1, RB2, WR1-3, or TE), bumping whoever was there
out of the roster entirely, or discard the pick and leave the roster exactly
as round 13 left it. That decision is theirs alone and happens after the
guess window has already closed — it isn't itself something another player
gets to guess at or block. A player happy with all seven of their skill picks
can, and often should, just discard.

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

**Table size — two to six.** The sabotage window is free-for-all rather than
turn-based, so nothing about the round's shape changes with player count the
way it would in a turn-based game like the auction. Six is a soft ceiling
rather than a measured one — pushed further and fourteen rounds of simultaneous
picks plus a crowded guessing window each round risks turning into a long
sit, but that's a pacing question for playtesting, not a structural limit.

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

**Modes** — unresolved. Like the auction, this game's whole hook is other
people trying to wreck your draft, which argues against a solo mode existing
at all in the same way "an auction needs opponents" argues against one there.

### Open questions

- [ ] **Data scope** — is the OL/DL/LB/CB/S/ST + AV pipeline in scope at all,
      given every other game in the app reads from one existing pool and this
      is a second one? This is the load-bearing open question; everything
      else here assumes it's solved.
- [ ] **Party point mapping** — cross-cutting, still unanswered for the other
      three games too. See `app.md`.
- [ ] **Disconnects** — what happens to a player's in-progress pick or an
      open guess window if they drop mid-round?
