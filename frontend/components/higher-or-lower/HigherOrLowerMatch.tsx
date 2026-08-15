import { Card, CardMeta, CardTitle } from "@/components/ui/Card";
import { Concealed } from "@/components/ui/Concealed";
import {
  cardMetaLine,
  eraLabel,
  formatPoints,
  questionPair,
  scoringModeLabel,
  type Board,
  type Card as LadderCard,
  type Player,
} from "@/lib/higher-or-lower/board";

/**
 * The ladder, on one screen.
 *
 * At this slice the screen is a rendering of a dealt board and nothing else:
 * the anchor face up, the challenger with its points withheld, and the two
 * numbers that say where in the match the table is. There is no clock and
 * nothing to press, so there is nothing for a browser to do that a server
 * render does not already do — this becomes a client component in #25, when
 * the phase machine gives it deadlines to chase and state to reconcile.
 *
 * The withheld number is withheld by the server. The challenger's row simply
 * does not carry its points until its question reveals, so the concealed panel
 * below is an honest rendering of an absent value rather than a UI that knows
 * something it is choosing not to say. See migration 0032.
 */
export function HigherOrLowerMatch({
  viewerId,
  initial,
}: {
  viewerId: string;
  initial: { board: Board; cards: LadderCard[]; players: Player[] };
}) {
  const { board, cards, players } = initial;
  const { anchor, challenger } = questionPair(cards, board.currentQuestion);

  return (
    <main className="mx-auto flex w-full min-h-0 flex-1 flex-col gap-4 overflow-hidden px-4 pt-3 pb-4">
      <header className="flex shrink-0 items-baseline justify-between gap-3">
        <p className="font-mono text-[11px] tracking-[0.15em] text-fg-muted uppercase">
          Question {board.currentQuestion} of {board.questionCount}
        </p>
        <p
          role="note"
          aria-label="Board format"
          className="font-mono text-[11px] tracking-[0.13em] text-fg-muted uppercase"
        >
          {scoringModeLabel(board)} · {eraLabel(board)}
        </p>
      </header>

      {anchor && challenger ? (
        <div className="grid min-h-0 flex-1 gap-3 lg:grid-cols-2">
          <LadderCardPanel
            label="Anchor"
            card={anchor}
            caption="What the challenger is priced against."
          />
          <LadderCardPanel
            label="Challenger"
            card={challenger}
            caption="Higher or lower than the anchor?"
          />
        </div>
      ) : (
        <p className="text-sm text-fg-muted">Waiting for the next card…</p>
      )}

      {/* Both points panels are hidden from assistive technology, so this
          region is the complete announcement of what is on screen. */}
      <p role="status" className="sr-only">
        {anchor && challenger
          ? `Question ${board.currentQuestion} of ${board.questionCount}. ${anchor.display_name} scored ${formatPoints(anchor.points)} fantasy points. ${challenger.display_name} is hidden.`
          : ""}
      </p>

      <aside aria-label="The table" className="shrink-0">
        <ul className="flex flex-wrap gap-2">
          {players.map((player) => (
            <li
              key={player.user_id}
              className="rounded border border-line px-3 py-1.5 font-slab text-[15px] leading-none -skew-x-7 uppercase"
            >
              {player.display_name}
              {player.user_id === viewerId ? (
                <span className="ml-1.5 font-mono text-[11px] tracking-[0.13em] text-fg-muted">
                  YOU
                </span>
              ) : null}
            </li>
          ))}
        </ul>
      </aside>
    </main>
  );
}

/**
 * One card and its number. The same component for both sides of a question,
 * because they are the same card at two moments — every challenger becomes the
 * next anchor — and rendering them from two components is how the two drift.
 */
function LadderCardPanel({
  label,
  card,
  caption,
}: {
  label: string;
  card: LadderCard;
  caption: string;
}) {
  return (
    <section role="group" aria-label={label} className="flex min-h-0 flex-col gap-2">
      <p className="font-mono text-[10px] tracking-[0.15em] text-fg-muted uppercase">{label}</p>

      <Card className="flex min-h-0 flex-1 flex-col">
        {/* The portrait band keeps its height whether or not a shot exists: a
            player nflverse has no picture for must not change the geometry. */}
        <div className="min-h-24 flex-1 border-b border-dashed border-[#c7bfac] bg-panel-shade">
          {card.headshot_url ? (
            <img
              src={card.headshot_url}
              alt=""
              className="h-full w-full object-contain object-bottom [mask-image:linear-gradient(to_bottom,#000_58%,transparent_96%)]"
            />
          ) : null}
        </div>
        <CardTitle>{card.display_name}</CardTitle>
        <CardMeta>{cardMetaLine(card)}</CardMeta>
      </Card>

      {/* Both faces are out of the accessibility tree: a weave with three
          question marks and a big number are visual idioms, and the screen's
          status region says the whole thing in one ordered sentence instead —
          the same split the auction's reveal uses. */}
      {card.points === null ? (
        <Concealed label="Fantasy points, hidden until this question reveals" className="px-3.5 py-3">
          <div aria-hidden className="relative flex items-baseline justify-between gap-3">
            <span className="font-mono text-[11px] tracking-[0.15em] text-panel uppercase">
              Fantasy points
            </span>
            <span className="font-slab text-lg leading-none -skew-x-7 text-panel">? ? ?</span>
          </div>
        </Concealed>
      ) : (
        <div aria-hidden className="flex items-baseline justify-between gap-3 rounded-card bg-panel px-3.5 py-3 text-panel-fg shadow-card">
          <span className="font-mono text-[11px] tracking-[0.15em] text-panel-muted uppercase">
            Fantasy points
          </span>
          <span className="min-w-0 font-slab text-lg leading-none -skew-x-7 tabular-nums">
            {formatPoints(card.points)}
          </span>
        </div>
      )}

      <p className="font-mono text-[11px] tracking-[0.13em] text-fg-muted uppercase">{caption}</p>
    </section>
  );
}
