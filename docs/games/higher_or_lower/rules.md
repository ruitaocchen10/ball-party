# Higher or Lower

A short, simultaneous fantasy-football recall game for two to four players.
One card is face up with its fantasy points; the next card hides its points.
Everyone calls higher or lower, then the challenger reveals and becomes the
next anchor. The fixed main ladder has twelve questions, followed by five cards
reserved for sudden death.

The host chooses season-total or weekly PPR scoring and an era inside the pool.
Season total is the default. Weekly cards add their week and opponent, because
the thing a player is being asked to remember is a particular game rather than
an entire season.

## Winning

After the twelve-question main ladder, the highest total correct answers wins.
A tie on total correct is broken by the highest best streak. Only players still
tied on both measures enter sudden death: they answer the reserved cards until
one outlasts the others. If that field remains tied after every spare card, the
win is shared.

## Dealing

The dealer ranks the selected deck by points at deal time and compares cards by
their percentile distance. It starts from the middle of that deck, picks each
challenger from a controlled distance from the current anchor, and does not use
the same player twice. Points and quantiles remain private until a card reveals.

The distance schedule lives in `higher_or_lower_private.band(question_index)`.
It tightens exponentially instead of linearly, so an endless solo ladder can
continue past question twelve without reaching a zero-distance coin flip.

## Band schedule

The distance schedule was read against 100 deterministic deals for each of four
deck shapes (both scoring modes, full 2010–2025 and narrow 2023–2025) and
confirmed as shipped:

| Question | Quantile distance |
| --- | --- |
| 1 | 0.200–0.350 |
| 12 | 0.047–0.111 |
| Long-run floor | 0.040–0.100 |

Question one is about a quarter of the deck apart, question twelve is hard
(roughly eight percent), and the floor holds at any solo depth rather than
collapsing to a coin flip.

**Known weakness: deep-vs-deep questions.** `deep` (the pool's lowest
per-position season-finish band, never shown to players) is the best proxy for
a card a table cannot place. Season-total decks put a deep card on both sides in
33–37% of main questions, about four per twelve-card match; weekly decks 18–20%.
The band is deliberately not distorted to hide that. If playtesting shows these
calls are dead rather than difficult, the planned fix is a host difficulty
toggle (stars-only versus the full pool) that filters the deck before the
schedule runs.
