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

## Band tuning (#30)

The opening schedule was read against real, reproducible ladders before being
declared the shipped schedule. It remains:

| Question | Quantile distance |
| --- | --- |
| 1 | 0.200–0.350 |
| 12 | 0.047–0.111 |
| Long-run floor | 0.040–0.100 |

The sample was 100 deterministic deals for each of four deck shapes: both
scoring modes across the full 2010–2025 era and the narrow 2023–2025 era. Each
used `higher_or_lower_private.deal_board` with seed `n / 101` for `n = 1..100`;
the read-through included sample indices 11, 37, and 63 in each shape. Those ladders mixed
recognisable anchors and challengers — for example Travis Etienne / James Cook
and Tom Brady / Le'Veon Bell in wide season-total, and Alvin Kamara / Derrick
Henry / Jahmyr Gibbs in narrow weekly — without making the early calls free.
Question twelve still put familiar cards close enough to require a real read,
rather than reducing to equal points or an arbitrary pick.

| Deck | Mean question-1 gap | Mean question-12 gap | Mean spare-card gap |
| --- | ---: | ---: | ---: |
| Season total, 2010–2025 | 0.273 | 0.076 | 0.073 |
| Season total, 2023–2025 | 0.273 | 0.081 | 0.072 |
| Weekly, 2010–2025 | 0.277 | 0.080 | 0.074 |
| Weekly, 2023–2025 | 0.283 | 0.079 | 0.074 |

The shape is the intended one: question one is approachable because it is
about a quarter of the deck away; question twelve is hard, at roughly eight
percent; and spare cards remain close but not arbitrarily so. The asymptote was
checked directly at indices a solo ladder can reach: question 17 is
0.042–0.103, question 100 is 0.040000000000068–0.100000000000107, and question
1,000 is exactly 0.040–0.100. Solo therefore approaches the intended floor
rather than a schedule that eventually collapses.

### Deep-cut risk

`deep` is not exposed to players; it means the pool's lowest per-position
season-finish band. It is the closest measurable proxy for a card a table
cannot place. Across the twelve main questions (1,200 per deck), the observed
deep-versus-deep rates were:

| Deck | Deep vs. deep |
| --- | ---: |
| Season total, 2010–2025 | 398 / 1,200 (33.2%) |
| Season total, 2023–2025 | 440 / 1,200 (36.7%) |
| Weekly, 2010–2025 | 243 / 1,200 (20.3%) |
| Weekly, 2023–2025 | 217 / 1,200 (18.1%) |

That reads badly for season total: the narrow deck produces roughly four such
questions per twelve-card match, and even the full era produces four on
average. The band is intentionally not distorted to hide that deck-composition
problem. The next move, if playtesting confirms that these calls are dead rather
than difficult, is the planned host difficulty toggle (stars-only versus the
full pool); it can filter the deck before the existing schedule runs.

The band values are therefore explicitly confirmed, not revised. They keep the
same readable opening in both modes and era widths, preserve a meaningful hard
twelfth question, and leave the deck-composition decision separate from the
difficulty dial.
