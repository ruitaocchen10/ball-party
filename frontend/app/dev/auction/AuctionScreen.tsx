"use client";

/**
 * THE AUCTION SCREEN, WITH THE GAME TAKEN OUT. **This is the file to edit.**
 *
 * The JSX below was copied verbatim out of components/auction/AuctionMatch.tsx.
 * It renders through the same primitives — TopBar, Card, Concealed, Button —
 * and computes through the same helpers in lib/auction/board.ts, so what you
 * see is what the product currently is, not a sketch of it. Exactly two things
 * changed on the way in: the RPC handlers became inert props, and the state
 * AuctionMatch fetches now arrives from a frozen fixture.
 *
 * It is a COPY, so it drifts the moment either file is edited alone. That is
 * the deliberate trade: this can be hacked on freely with no way to break a
 * live match. When we settle on a change it gets ported back to
 * AuctionMatch.tsx by hand — or we do the real refactor and split the view out
 * of the wiring so both render one component.
 */

import { useCallback, useEffect, useRef, useState, type Ref } from "react";
import Link from "next/link";

import { TopBar } from "@/components/layout/TopBar";
import { Button } from "@/components/ui/Button";
import { Card, CardMeta, CardTitle } from "@/components/ui/Card";
import { Concealed } from "@/components/ui/Concealed";
import {
  BLOCKED_TEXT,
  INCREMENTS,
  SLOTS,
  blockedReason,
  byPlacement,
  canAfford,
  filledSlots,
  hasPassed,
  highBidder,
  lotAt,
  matchupLine,
  revealedTotal,
  standingPrice,
  slotFor,
  viewerPhase,
  type AuctionPhase,
  type Lot,
  type Player,
  type Standing,
  type Slot,
  type Turn,
} from "@/lib/auction/board";
import { VIEWER_ID } from "./fixture";
import type { Scenario } from "./scenarios";

/* Copied from AuctionMatch.tsx — the bid bar reads these to size its clock. */
const VISIBLE_SLACK_MS = 500;
const TICK_MS = 100;
const DURATION_MS: Record<Turn["phase"], number> = {
  lot_preview: 5_000,
  bidding: 20_000,
  sold: 5_000,
};

const DISPLAY_NAME = "Dev";
const ROOM_CODE = "BLTZ";

/* ───────────────────── the product, copied from AuctionMatch ─────────────── */

/**
 * The render body of AuctionMatch, with its data coming from a scenario instead
 * of from Postgres. Everything between the <Screen> tags is verbatim.
 */
export function AuctionScreen({
  scenario,
  remainingMs,
  stamped = false,
}: {
  scenario: Scenario;
  remainingMs: number | null;
  /* A/B only, not a product flag. false is the screen as it ships. true says
     the blocked states with the cards instead of with words: the lot card gets
     an out-of-play stamp (see OutStamp) and the rail's three status labels give
     way to seat states (see PlayerRail). */
  stamped?: boolean;
}) {
  const {
    players,
    lots,
    bids,
    turn: turnState,
    standings = [],
    finished = false,
  } = scenario;
  const displayName = DISPLAY_NAME;
  const viewerId = VIEWER_ID;
  const roomCode = ROOM_CODE;
  const me = players.find((p) => p.user_id === viewerId) ?? null;
  const lot = lotAt(lots, turnState.currentLot);
  const turn = turnState;
  const phaseRemainingMs = remainingMs;
  const pending = false;
  const error: string | null = null;

  /* In the real component these fire RPCs. Here they are inert on purpose:
     this page is for looking at states, not for simulating an auction. */
  const onRaise = () => {};
  const onPass = () => {};

  if (finished) {
    return (
      <Screen displayName={displayName}>
        <FinalScreen
          lots={lots}
          players={players}
          standings={standings}
          viewerId={viewerId}
          roomCode={roomCode}
        />
      </Screen>
    );
  }

  if (!lot) {
    return (
      <Screen displayName={displayName}>
        <p className="text-sm text-fg-muted">Waiting for the next lot…</p>
      </Screen>
    );
  }

  const price = standingPrice(bids, lot.seq);
  const holder = highBidder(bids, lot.seq);
  const filled = me
    ? filledSlots(lots, me.user_id)
    : { QB: 0, RB: 0, WR: 0, TE: 0, FLEX: 0 };
  const passed = me ? hasPassed(bids, lot.seq, me.user_id) : false;
  const onClock = players.find((p) => p.seat === turn.turnSeat) ?? null;
  const phase = viewerPhase(turn, me?.seat ?? null);
  const blocked = me
    ? blockedReason({
        lot,
        me,
        turnSeat: turn.turnSeat,
        filled,
        format: null,
        passed,
        price,
      })
    : "not_your_turn";

  /* Only the SETTLED blocks stamp the card — the two where nothing that happens
     in the next eighteen seconds puts you back in this lot.

     `not_your_turn` is transient and would strobe the biggest object on screen
     once per seat per lot. `cannot_afford` is not an exit at all: board.ts is
     explicit that an empty wallet costs contested lots and never costs slots,
     and since blockedReason only reaches it on your own turn you can hit it
     while holding the high bid — stamping there would call you out at the
     moment you are winning.

     Sold clears it, or the reveal lands on a card still marked dead. */
  const out =
    phase !== "sold" && (blocked === "passed" || blocked === "no_slot")
      ? blocked
      : null;

  return (
    <Screen displayName={displayName} workspace>
      <LotStrip lots={lots} players={players} turn={turn} phase={phase} />

      {/* Three named regions: THE CONTROLS (what you can do about this lot),
          THE LOT (what is being sold), THE TABLE (everyone's money).

          Stacked below 1024px, side by side at and above it. The mobile row
          template is the whole of story 8: the Lot is sized to its content and
          never compressed, and the Table takes what is left and scrolls inside
          itself. Without it both rows are auto and a four-seat table pushes the
          live auction off the screen. The Controls sit auto between them.

          DOM order is the phone's reading order — what is this, what do I do
          about it, who am I playing against — and the desktop columns are
          placed explicitly so the controls can sit on the left without the
          screen reader meeting them before the card they act on. */}
      <div className="grid min-h-0 flex-1 grid-rows-[auto_auto_minmax(6rem,1fr)] gap-3 lg:grid-cols-[minmax(15rem,.62fr)_minmax(0,1fr)_minmax(21rem,.95fr)] lg:grid-rows-1">
        <section
          className="flex min-h-0 flex-col gap-2 lg:col-start-2 lg:row-start-1"
          aria-label="The lot"
        >
          {/* The lot. Red top edge, because there is concealed information behind
          it — which is the rule Card already documents. */}
          <Card className="flex min-h-0 flex-1 flex-col">
            {stamped && out !== null ? <OutStamp reason={out} /> : null}
            {/* The portrait band is the Lot's only flexible-height element, and it
            keeps its height whether or not a shot exists — a player nflverse
            has no picture for must not change the geometry under a live clock. */}
            <div className="min-h-24 flex-1 border-b border-dashed border-[#c7bfac] bg-panel-shade">
              {lot.headshot_url ? (
                <img
                  src={lot.headshot_url}
                  alt=""
                  className="h-full w-full object-contain object-bottom [mask-image:linear-gradient(to_bottom,#000_58%,transparent_96%)]"
                />
              ) : null}
            </div>
            <CardTitle>{lot.display_name}</CardTitle>
            <CardMeta>{matchupLine(lot)}</CardMeta>
          </Card>

          {/* The fantasy points. One bar, not two states of the world: it is
          the same object concealed and revealed, so the payoff is watching
          THIS shape flip rather than watching a second card appear beside it.
          Sold is the only trigger — the weave holds through lot_preview and
          bidding, where the number is still somebody else's to know. */}
          {phase === "sold" ? (
            <RevealedPoints lot={lot} />
          ) : (
            <Concealed
              label="Fantasy points, hidden until this lot is won"
              className="px-3.5 py-3"
            >
              <div className="relative flex items-baseline justify-between gap-3">
                <span className="font-mono text-[10px] tracking-[0.15em] text-panel uppercase">
                  Fantasy points
                </span>
                <span className="font-slab text-lg leading-none -skew-x-7 text-panel">
                  ? ? ?
                </span>
              </div>
            </Concealed>
          )}
        </section>

        {/* The controls, in their own column rather than bolted to the foot of
            the card. The card is the thing you study and the controls are the
            thing you operate, and they were sharing a column only because the
            phone has one. */}
        <section
          className="flex min-h-0 flex-col lg:col-start-1 lg:row-start-1"
          aria-label="The controls"
        >
          {me ? (
            <BidBar
              phase={phase}
              price={price}
              budget={me.budget}
              remainingMs={
                phase === "bidding_self" || phase === "bidding_other"
                  ? remainingMs
                  : phaseRemainingMs
              }
              onClock={onClock}
              isMine={phase === "bidding_self"}
              blocked={blocked}
              pending={pending}
              error={error}
              slot={slotFor(lot)}
              onRaise={onRaise}
              onPass={onPass}
            />
          ) : (
            <p className="min-h-17 text-sm text-fg-muted">
              You&apos;re watching this one.
            </p>
          )}
        </section>

        <aside
          className="min-h-0 overflow-y-auto lg:col-start-3 lg:row-start-1"
          aria-label="The table"
        >
          <PlayerRail
            players={players}
            lots={lots}
            viewerId={viewerId}
            turnSeat={turn.turnSeat}
            holder={holder}
            passedSeats={players
              .filter((p) => hasPassed(bids, lot.seq, p.user_id))
              .map((p) => p.seat)}
            soldLot={phase === "sold" ? lot : null}
            price={price}
            useCardStateIndicators={stamped}
          />
        </aside>
      </div>
    </Screen>
  );
}

/**
 * THE STRIP. The board as a row, and what stands where the app's top bar used
 * to — see Screen for why the bar goes, and why nothing of it was kept.
 *
 * It is doing a job nothing else on this screen does. The rail says who owns
 * what; the strip says what happened, in the order it happened, and for how
 * much. Price is the point of it: the rail carries rosters and running totals
 * but has never once said what anything cost, in a game whose entire currency
 * is knowing that somebody got a 29-point week for $3.
 *
 * Three kinds of cell, in board order:
 *
 *   SOLD      face, player, the slot it filled, the price, the winner
 *   CURRENT   wide, the lot number and where the beat is
 *   UPCOMING  an empty frame and its number
 *
 * The upcoming cells leak nothing. They are drawn from `turn.lotCount`, not
 * from the lots array — the server has not sent the undealt ones and this
 * component could not name them if it wanted to. What they show is how many
 * are left, which `Lot 3 of 20` already said out loud. Blind visibility, per
 * the design doc, is about card identities and stays intact.
 */
function LotStrip({
  lots,
  players,
  turn,
  phase,
}: {
  lots: Lot[];
  players: Player[];
  turn: Turn;
  phase: AuctionPhase;
}) {
  const rail = useRef<HTMLOListElement>(null);
  const current = useRef<HTMLLIElement>(null);

  /* The strip follows the auction rather than the auction following the strip.
     Twenty lots do not fit at any width we care about, so the live one is kept
     centred and the history runs off to the left where it can be scrolled back
     to. `smooth` because it moves once every twenty seconds and the movement
     is itself the signal that a lot resolved. */
  useEffect(() => {
    current.current?.scrollIntoView({
      behavior: "smooth",
      inline: "center",
      block: "nearest",
    });
  }, [turn.currentLot]);

  return (
    <ol
      ref={rail}
      aria-label="The board"
      className="flex shrink-0 gap-1.5 overflow-x-auto scroll-smooth pb-1 [scrollbar-width:thin]"
    >
      {Array.from({ length: turn.lotCount }, (_, index) => index + 1).map(
        (seq) => {
          if (seq === turn.currentLot)
            return (
              <CurrentCell
                key={seq}
                ref={current}
                seq={seq}
                lotCount={turn.lotCount}
                phase={phase}
              />
            );

          const sold = lots.find((l) => l.seq === seq) ?? null;
          return sold && seq < turn.currentLot ? (
            <SoldCell key={seq} lot={sold} players={players} />
          ) : (
            <UpcomingCell key={seq} seq={seq} />
          );
        },
      )}
    </ol>
  );
}

/** Fixed at every cell so the strip is a row of equals and the live lot is the
 *  only thing that breaks the rhythm. */
const CELL = "h-[74px] shrink-0 rounded border px-1.5 py-1";

/**
 * A lot that has happened. Everything a settled lot is worth remembering:
 * what it was, what it filled, what it went for, and who has it now.
 *
 * The price is the loudest thing in the cell after the face. It is the number
 * this screen has never shown anywhere else, and reading a row of them is how
 * you learn what the table thinks a back is worth tonight.
 */
function SoldCell({ lot, players }: { lot: Lot; players: Player[] }) {
  const winner = players.find((p) => p.user_id === lot.winner_id) ?? null;

  return (
    <li
      className={`${CELL} flex w-[84px] flex-col border-line bg-surface-raised`}
      aria-label={`Lot ${lot.seq}, ${lot.display_name}, ${lot.slot ?? "unfilled"}, ${
        lot.price === null ? "no price" : `$${lot.price}`
      }, won by ${winner?.display_name ?? "nobody"}`}
    >
      <p className="flex items-baseline justify-between gap-1 font-mono text-[9px] leading-none tracking-[0.1em] text-fg-muted uppercase">
        <span>{lot.slot}</span>
        <span className="font-bold text-fg tabular-nums">
          {lot.price === null ? "—" : `$${lot.price}`}
        </span>
      </p>

      <span className="mx-auto mt-1 block h-7 w-7 shrink-0 overflow-hidden rounded-full bg-panel-shade">
        {lot.headshot_url ? (
          <img
            src={lot.headshot_url}
            alt=""
            className="h-full w-full object-cover object-top"
          />
        ) : null}
      </span>

      <p className="mt-1 truncate text-center font-slab text-[10px] leading-none -skew-x-7 uppercase">
        {abbreviate(lot.display_name)}
      </p>
      <p className="mt-1 truncate text-center font-mono text-[8px] leading-none tracking-[0.08em] text-fg-muted uppercase">
        {winner ? winner.display_name : "No bids"}
      </p>
    </li>
  );
}

/**
 * The lot on the table. Wide, because it is the one cell that has to be found
 * without being looked for, and because a strip of identical squares gives the
 * eye nothing to land on.
 *
 * It carries the phase rather than the seconds. The clock is in the controls
 * where the decision is; what this says is which beat of the lot we are in,
 * which is the thing you want when your eyes are somewhere else on the screen.
 */
function CurrentCell({
  seq,
  lotCount,
  phase,
  ref,
}: {
  seq: number;
  lotCount: number;
  phase: AuctionPhase;
  ref?: Ref<HTMLLIElement>;
}) {
  return (
    <li
      ref={ref}
      aria-current="step"
      className={`${CELL} flex w-[164px] flex-col justify-center border-panel/45 bg-panel/10 px-3`}
    >
      <p className="font-slab text-lg leading-none -skew-x-7 uppercase">
        Lot {seq}
        <span className="ml-1.5 font-mono text-[10px] tracking-[0.1em] text-fg-muted">
          / {lotCount}
        </span>
      </p>
      <p className="mt-1.5 font-mono text-[9px] tracking-[0.13em] text-fg-muted uppercase">
        {phase === "lot_preview"
          ? "Coming up"
          : phase === "sold"
            ? "Sold"
            : "On the clock"}
      </p>
    </li>
  );
}

/** A lot that has not been dealt. An empty frame and a number: it says one is
 *  coming and nothing else, because nothing else is known to this component. */
function UpcomingCell({ seq }: { seq: number }) {
  return (
    <li
      aria-label={`Lot ${seq}, not yet dealt`}
      className={`${CELL} flex w-[84px] flex-col items-center justify-center gap-2 border-dashed border-line bg-transparent`}
    >
      <span
        aria-hidden
        className="block h-7 w-7 rounded-full border border-dashed border-line"
      />
      <span className="font-mono text-[9px] leading-none tracking-[0.1em] text-fg-muted tabular-nums">
        {seq}
      </span>
    </li>
  );
}

/** "Patrick Mahomes" in 84px is "P. MAHOMES". The surname is the recall cue and
 *  the initial is what keeps two Williamses apart. */
function abbreviate(name: string): string {
  const parts = name.trim().split(/\s+/);
  if (parts.length < 2) return name;
  return `${parts[0][0]}. ${parts.slice(1).join(" ")}`;
}

/**
 * The lot, marked out of play.
 *
 * One state answers "am I in this?" at a glance — a job carried today only by a
 * 12px sentence under three grey buttons, which is the smallest thing on screen
 * doing the most important work. The word inside the stamp keeps the answer to
 * "why not?", which board.ts argues for and is right about: an unexplained dead
 * card, in a game this full of legitimately hidden things, reads as broken
 * rather than as a rule.
 *
 * A veil rather than a filter on the Card, because a CSS filter applies to
 * descendants and would grey the stamp along with the portrait. `bg-panel/70`
 * washes the card out and `backdrop-grayscale` drains the photo behind it,
 * neither of which touches the stamp — the player stays legible, which is the
 * point. Watching the back you cannot have go for $3 is the drama, not noise.
 *
 * --hidden-ink is the red the token file reserves for marks that must stay
 * legible ON a cream panel, so the stamp lands in the same family as the weave
 * and the top edge: red is the game acting on you.
 *
 * aria-hidden because the bid bar already says this in BLOCKED_TEXT, and a
 * screen reader should hear the reason once.
 */
function OutStamp({ reason }: { reason: "passed" | "no_slot" }) {
  return (
    <span
      aria-hidden
      className="absolute inset-0 z-10 flex items-center justify-center bg-panel/70 backdrop-grayscale"
    >
      <span className="-rotate-6 rounded-[4px] border-[3px] border-hidden-ink/70 px-4 py-2 font-slab text-[22px] leading-none tracking-[0.04em] text-hidden-ink/80 uppercase lg:px-5 lg:text-[28px]">
        {reason === "passed" ? "Passed" : "Slot filled"}
      </span>
    </span>
  );
}

export function Screen({
  displayName,
  children,
  workspace = false,
}: {
  displayName: string | null;
  children: React.ReactNode;
  workspace?: boolean;
}) {
  return (
    <>
      {/* NO TOP BAR IN A LIVE MATCH. The brand is a link to /, which is a
          single mis-tap that drops you out of a lot with a clock running, and
          the account menu holds profile, settings and sign out — none of which
          anybody wants in the middle of a twelve-minute game. What it cost was
          56px of the one screen in this app that never scrolls.

          Identity, the one thing it was really there for, is answered better
          by the rail: your seat carries a YOU tag next to your own money.

          The account menu went with it rather than being demoted into the
          strip. Every item in that menu — profile, settings, sign out —
          navigates out of a live match, so keeping it as an "escape hatch"
          was keeping a trapdoor: an affordance whose whole content is leaving,
          sat one mis-tap above the board. It also cost the strip 140px of the
          width it least has to spare.

          Which leaves a live match with NO EXIT but the browser's back button.
          That is a real gap and it is deliberate for now: the exit worth
          building is "back to the room", and it belongs somewhere chosen
          rather than inherited from a menu that was never about this game.

          The final screen still gets the chrome — the game is over, you are a
          user again. */}
      {workspace ? null : <TopBar displayName={displayName} />}
      {/* Two shapes, and the padding belongs to each of them rather than to
          both. A reading screen is one column, thumb-width, because four people
          around a table are all holding phones — margin is what makes it
          readable. The workspace is the opposite: it never scrolls, so every
          pixel spent on a gutter is a pixel taken off the card, the rail, or
          the roster rows, and it should run as close to the edge as it can.

          So the workspace is uncapped and its gutter is a flat 16px at every
          width. No max-width, because a cap is a margin by another name: at
          1512 a max-w-7xl container was throwing away 116px a side before the
          padding even started, and the auction is a screen that wants to fill
          the window rather than a document that wants to be read at a
          comfortable measure. No px ramp either — the wider the window, the
          more the gutter should get out of the way, which is the opposite of
          what a ramp does.

          The cost, stated plainly: TopBar's row still sits in a centred
          max-w-7xl, so above 1280 the brand is inboard of the lot rather than
          flush with it. That is the trade for the width, and the fix if it
          bothers us is on TopBar, not here. */}
      <main
        className={`mx-auto flex w-full flex-1 flex-col ${
          workspace
            ? "min-h-0 gap-3 overflow-hidden px-4 pt-3 pb-4"
            : "max-w-md gap-4 px-5 pt-4 pb-4"
        }`}
      >
        {children}
      </main>
    </>
  );
}

/**
 * The fantasy points bar, unmasked. Same footprint as <Concealed> — same
 * rounded bar, same padding, same label-left/number-right layout — because
 * the payoff is this shape losing its weave, not a second card landing under
 * it. Red goes to cream and "? ? ?" becomes the number, which is the whole
 * of what "revealed" means for a stat nothing else on screen was hiding.
 *
 * Who won it and what it cost are not repeated here: the winner's seat in
 * the rail is already carrying the sold flourish and the bid bar is already
 * holding the price, so this bar has exactly one fact to add.
 *
 * `animate-sold-once` ties it to the same beat as the rail's highlighted
 * seat — the two places the reveal actually lands flash together rather than
 * on their own clocks.
 */
function RevealedPoints({ lot }: { lot: Lot }) {
  return (
    <div
      role="status"
      aria-label={`Fantasy points, ${fmt(lot.points)}`}
      className="rounded-card bg-panel px-3.5 py-3 text-panel-fg shadow-card motion-safe:animate-sold-once"
    >
      <div className="flex items-baseline justify-between gap-3">
        <span className="font-mono text-[10px] tracking-[0.15em] text-panel-muted uppercase">
          Fantasy points
        </span>
        <span className="font-slab text-lg leading-none -skew-x-7">
          {fmt(lot.points)}
        </span>
      </div>
    </div>
  );
}

/**
 * Everyone's budget and running total, always on screen, which is what lets a
 * player tell whether they are chasing or protecting. Rosters ride along so you
 * can read what the others still need.
 *
 * A seat collapses to two lines — name and budget on top, which slots are
 * taken underneath. Open, the second line becomes the full roster of cards.
 * Your own seat starts open and everyone else's starts closed: yours is the
 * one you act on, theirs is reference you go and look up. That is also what
 * keeps four seats on one screen once the rosters fill, which stacked cards
 * cannot do.
 *
 * The running total leads the row now, at the far right and the largest thing
 * on it apart from the name — a reversal of the earlier draft, which buried it
 * in 11px mono beside the budget. In a game whose entire premise is trading
 * money for points, the total is the scoreboard; the budget is what is left to
 * spend, not the thing anyone is being ranked on, and it moved out to its own
 * outlined chip so the two stop sharing a baseline.
 *
 * A win does NOT pop the seat open. The chip for the slot just lights up where
 * it already sits, so nothing on screen jumps at the moment the reveal lands in
 * the lot column — that beat belongs to the card, not to the rail.
 */
function PlayerRail({
  players,
  lots,
  viewerId,
  turnSeat,
  holder,
  passedSeats,
  soldLot,
  price,
  useCardStateIndicators = false,
}: {
  players: Player[];
  lots: Lot[];
  viewerId: string;
  turnSeat: number | null;
  holder: string | null;
  passedSeats: number[];
  soldLot: Lot | null;
  price: number;
  /* A/B only. false is the rail as it ships — three status words under each
     roster. true drops the words and says the same three things with the seat
     itself: dimmed, raised, or holding a price. */
  useCardStateIndicators?: boolean;
}) {
  /* Keyed by user rather than held as a single "which one is open", because
     these are independent: studying Toby's roster is no reason to close your
     own. */
  const [open, setOpen] = useState<Record<string, boolean>>(() => ({
    [viewerId]: true,
  }));
  const toggle = (userId: string) =>
    setOpen((prev) => ({ ...prev, [userId]: !(prev[userId] ?? false) }));

  return (
    <ul className="flex flex-col gap-2 lg:gap-1.5">
      {players.map((player) => {
        const acting = player.seat === turnSeat;
        const total = revealedTotal(lots, player.user_id);
        const holding = holder === player.user_id;
        const isOpen = open[player.user_id] ?? false;
        const highlightSlot =
          soldLot?.winner_id === player.user_id ? soldLot.slot : null;
        /* Out of THIS lot, not out of the game — which is why it is a wash and
           not a strike-through. Their budget and running total stay readable on
           purpose: those are what you are playing against, and they do not stop
           mattering because someone folded on one back. */
        const out =
          useCardStateIndicators &&
          passedSeats.includes(player.seat) &&
          !acting;

        return (
          <li
            key={player.user_id}
            className={`rounded border px-3 py-2.5 transition-colors lg:py-3 ${
              soldLot?.winner_id === player.user_id
                ? "border-panel bg-panel/10 motion-safe:animate-sold-once"
                : acting
                  ? "border-panel/45 bg-surface-raised"
                  : out
                    ? "border-line/40 opacity-45 saturate-50"
                    : "border-line bg-transparent"
            }`}
          >
            {/* The whole header block is the control — two lines when closed,
                one when open, both of them clickable. A separate disclosure
                button would be one more thing to aim at in a column that is
                already the narrow one, and there is nothing else in this row
                to click. */}
            <button
              type="button"
              onClick={() => toggle(player.user_id)}
              aria-expanded={isOpen}
              className="flex w-full flex-col gap-2 text-left lg:gap-1.5"
            >
              <span className="flex items-center gap-2">
                <span
                  aria-hidden
                  className={`shrink-0 font-mono text-[10px] leading-none text-fg-muted transition-transform ${isOpen ? "rotate-90" : ""}`}
                >
                  &#9656;
                </span>
                <span className="truncate font-slab text-[15px] leading-none -skew-x-7 uppercase">
                  {player.display_name}
                  {player.user_id === viewerId ? (
                    <span className="ml-1.5 font-mono text-[9px] tracking-[0.13em] text-fg-muted">
                      YOU
                    </span>
                  ) : null}
                </span>

                {/* Budget, in its own outlined chip rather than riding the
                    baseline with the total — the two are different kinds of
                    number and no longer share a typographic register. */}
                <span className="shrink-0 rounded border border-line px-1.5 py-0.5 font-mono text-[10px] text-fg-muted tabular-nums">
                  ${player.budget}
                </span>

                {/* The standing bid, on the seat that owns it. "High bid" was a
                    label; this is the number, which is more use in a game about
                    money — and it is the one of the three states a dimmed-or-
                    raised card cannot carry, because holding the bid is good news
                    and both of those read as loud or quiet, not as winning.

                    No longer behind the A/B: the controls now say what the price
                    is and the rail says whose it is, which is each fact once. */}
                {holding ? (
                  <span className="shrink-0 rounded-[3px] bg-panel px-1.5 py-0.5 font-mono text-[10px] font-bold text-panel-fg tabular-nums">
                    ${price}
                  </span>
                ) : null}

                {/* The running total. Largest thing on the row after the name,
                    plain bold rather than slab or mono — it is a scoreboard
                    figure, not a card's headline number, and it earns its own
                    register precisely by not borrowing either of theirs. */}
                <span
                  className="ml-auto shrink-0 text-lg font-bold tabular-nums lg:text-xl"
                  aria-label={`${fmt(total)} points`}
                >
                  {fmt(total)}
                </span>
              </span>

              {/* Closed, the slots come up here as a second line — which ones
                  are taken is the thing you scan for, and the total is already
                  answered above. */}
              {isOpen ? null : (
                <Roster
                  lots={lots}
                  userId={player.user_id}
                  highlightSlot={highlightSlot}
                  compact
                />
              )}
            </button>

            {isOpen ? (
              /* Phone: roster and status share one line, because vertical space
                 is the scarce thing. Desktop: column-reverse lifts the status
                 word up under the roster it belongs with. */
              <div className="mt-2 flex items-center justify-between gap-2 lg:mt-1.5 lg:flex-col-reverse lg:items-stretch lg:gap-1">
                <Roster
                  lots={lots}
                  userId={player.user_id}
                  highlightSlot={highlightSlot}
                />
                {/* "High bid" has left the word list: the chip on the seat
                    header carries it now, at every seat, open or closed. What
                    is left are the two states the chip cannot say. */}
                {useCardStateIndicators ? null : (
                  <span className="shrink-0 font-mono text-[9px] tracking-[0.13em] text-fg-muted uppercase lg:text-right">
                    {acting
                      ? "on the clock"
                      : passedSeats.includes(player.seat)
                        ? "passed"
                        : ""}
                  </span>
                )}
              </div>
            ) : null}
          </li>
        );
      })}
    </ul>
  );
}

/** Filled slots show what they hold. Unfilled ones are a dashed gap — an empty
 *  slot is absent, not withheld, and the concealed weave is reserved for the
 *  fantasy points, which exist and are being kept from you.
 *
 *  `compact` is the collapsed seat: slot labels only, no name and no points,
 *  because the seat header above it already carries the running total and
 *  what you are scanning a closed seat for is which positions are gone.
 *
 *  Otherwise, two layouts from one markup. On a phone the five slots stay a row
 *  of chips: everything but `QB 35.9` is dropped, because five chips across a
 *  thumb-width column is all the room there is. On the web a won slot becomes a
 *  single line — slot, name, the fixture that made it, and the points — so the
 *  rail reads as the four collections being built rather than as a scoreboard.
 *  No portrait here: at one line tall there is no room for one without either
 *  shrinking the type below its floor or growing the row back into a card, and
 *  the lot column already carries the face for whichever player is live.
 *
 *  All five slots are always rendered, so the reader can see what everyone
 *  still needs; that is half the point of the rail. It is one wrapping row at
 *  both widths: on the web a won slot takes `w-full` and gets a line to itself,
 *  while the slots still open stay chip-sized and pack together, so four seats'
 *  rosters still fit on one screen instead of becoming twenty stacked cards. */
function Roster({
  lots,
  userId,
  highlightSlot = null,
  compact = false,
}: {
  lots: Lot[];
  userId: string;
  highlightSlot?: string | null;
  compact?: boolean;
}) {
  return (
    <ul className="flex flex-wrap gap-1">
      {SLOTS.map((slot) => {
        const won =
          lots.find((l) => l.winner_id === userId && l.slot === slot) ?? null;
        /* The sold beat, on a slot that may be sitting in a closed seat: the
           chip lights up where it already is rather than the seat opening
           under it. */
        const lit =
          highlightSlot === slot
            ? "ring-2 ring-panel motion-safe:animate-sold-once"
            : "";

        if (compact) {
          return (
            <li key={slot}>
              <span
                aria-label={
                  won
                    ? `${slot} slot, ${won.display_name}`
                    : `${slot} slot, empty`
                }
                /* The empties drop out at phone width. A closed seat there is
                   name, budget, slots on one 402px line, and five chips plus a
                   name does not fit — so the phone keeps the slots that are
                   GONE, which is the ask, and the web keeps all five because it
                   has room to also say what is still open. */
                className={`h-6 items-center justify-center rounded-[3px] px-2 font-mono text-[9px] tracking-[0.1em] lg:text-[10px] ${
                  won
                    ? "flex bg-panel font-bold text-panel-fg"
                    : "hidden border border-dashed border-fg-muted/70 text-fg-muted lg:flex"
                } ${lit}`}
              >
                {slot}
              </span>
            </li>
          );
        }

        return (
          <li key={slot} className={won ? "lg:w-full" : undefined}>
            {won ? (
              <span
                aria-label={`${slot} slot, ${won.display_name}, ${won.season} week ${won.week} versus ${won.opponent}, ${fmt(won.points)} points`}
                className={`flex h-7 items-baseline gap-1.5 overflow-hidden rounded-[3px] bg-panel px-1.5 font-mono text-[9px] text-panel-fg tabular-nums lg:h-auto lg:gap-2 lg:px-2.5 lg:py-1.5 ${lit}`}
              >
                <span className="shrink-0 tracking-[0.1em] text-panel-muted">
                  {slot}
                </span>
                {/* Abbreviated the same way LotStrip's sold cells are — first
                    initial, last name — so a won lot reads the same wherever it
                    shows up on this screen. */}
                <span className="hidden shrink-0 truncate font-bold text-[13px] leading-none lg:block">
                  {abbreviate(won.display_name)}
                </span>
                {/* Year, week and matchup: the recall cues. Position rides
                    along only when the slot does not already say it, which is
                    exactly the flex case. */}
                <span className="hidden min-w-0 flex-1 truncate font-mono text-[9px] leading-none tracking-[0.08em] text-panel-muted uppercase lg:block">
                  {won.slot === won.position ? null : `${won.position} · `}
                  {won.season} · Wk {won.week} · vs {won.opponent}
                </span>
                <span className="ml-auto shrink-0 font-bold lg:text-[17px] lg:leading-none">
                  {fmt(won.points)}
                </span>
              </span>
            ) : (
              <span
                aria-label={`${slot} slot, empty`}
                className="flex h-7 items-center justify-center rounded-[3px] border border-dashed border-fg-muted/70 px-2 font-mono text-[9px] tracking-[0.1em] text-fg-muted lg:h-6 lg:text-[10px]"
              >
                {slot}
              </span>
            )}
          </li>
        );
      })}
    </ul>
  );
}

/**
 * The controls, as two stacked panels rather than one tower or a bar under
 * the card. On a phone it is still a block at the bottom of the scroll,
 * thumb-height; on the web it is the left column. Both panels sit on
 * --surface-raised, which the token file already annotates as where a bid bar
 * goes.
 *
 * Two panels because they answer two different questions. THE CLOCK says
 * whose turn it is and how long is left — one fact, and the phase label is
 * part of it, since "0:14" means nothing without knowing on whom. THE BID
 * says what winning costs and what spends a chance: price, raises, Pass. A
 * single box was implying those were one fact when they are not — the clock
 * moves every tick regardless of what anyone does, the price only moves when
 * somebody acts on it — and splitting them is why the clock can lead its own
 * panel without shrinking the price out of the other one.
 *
 * The clock leads its panel rather than the price leading the old tower — a
 * reversal of the earlier draft, which reasoned the price was "the number the
 * whole game turns on." But the price only changes on a bid; the clock is the
 * number a player is under the most pressure to read correctly, every second
 * of every turn. It runs mm:ss rather than a bare "8s" so it reads as a
 * countdown rather than a label, even though no phase in this game is long
 * enough to ever show a minute.
 *
 * A disabled control always says why. Four different situations produce the
 * same greyed button otherwise, and "you already have a quarterback" being
 * indistinguishable from a broken app is the difference between a rule and a
 * bug.
 */
function BidBar({
  phase,
  price,
  budget,
  remainingMs,
  onClock,
  isMine,
  blocked,
  pending,
  error,
  slot,
  onRaise,
  onPass,
}: {
  price: number;
  budget: number;
  remainingMs: number | null;
  onClock: Player | null;
  isMine: boolean;
  blocked: ReturnType<typeof blockedReason>;
  pending: boolean;
  onRaise: (amount: number) => void;
  onPass: () => void;
  phase: "lot_preview" | "bidding_self" | "bidding_other" | "sold";
  error: string | null;
  slot: Slot;
}) {
  const [customFor, setCustomFor] = useState<string | null>(null);
  const [amount, setAmount] = useState(String(price + 1));
  const input = useRef<HTMLInputElement>(null);
  const customButton = useRef<HTMLButtonElement>(null);
  const surface = useRef<HTMLDivElement>(null);
  const minimum = price + 1;
  // Keying the popover to the interaction rather than to a boolean is what
  // closes it on a turn change, a new price or a sale: the key it was opened
  // against simply stops being the current one.
  const interactionKey = `${phase}:${onClock?.seat ?? "none"}:${price}`;
  const custom = customFor === interactionKey;
  const actionable = phase === "bidding_self" && blocked === null && !pending;

  // Focus goes back where it came from on Escape and Cancel. It cannot on an
  // auto-close -- the phase change that closed the popover is the same one that
  // disabled the Custom button -- so those land on the control surface instead,
  // which keeps a keyboard user in the controls rather than at the document top.
  const dismissed = useRef(false);
  const wasOpen = useRef(false);
  const closeCustom = useCallback(() => {
    dismissed.current = true;
    setCustomFor(null);
  }, []);
  useEffect(() => {
    if (custom) {
      wasOpen.current = true;
      input.current?.focus();
      return;
    }
    if (!wasOpen.current) return;
    wasOpen.current = false;
    if (dismissed.current) {
      dismissed.current = false;
      customButton.current?.focus();
    } else surface.current?.focus();
  }, [custom]);
  const seconds = remainingMs === null ? null : Math.ceil(remainingMs / 1000);
  const live = phase === "bidding_self" || phase === "bidding_other";
  const fraction =
    remainingMs === null
      ? 0
      : Math.min(
          1,
          remainingMs /
            (live
              ? DURATION_MS.bidding - VISIBLE_SLACK_MS
              : DURATION_MS[phase === "sold" ? "sold" : "lot_preview"]),
        );
  const urgent = seconds !== null && seconds <= 3 && live;
  // Which state the clock panel itself signals. Urgent wins over "it's your
  // turn": a card reading red at three seconds means the same thing whether
  // the clock is yours or somebody else's, and "yours, calm" versus "yours,
  // about to expire" should not look identical.
  const clockTone = urgent ? "urgent" : isMine ? "mine" : "waiting";
  const invalid =
    !Number.isInteger(Number(amount)) ||
    Number(amount) < minimum ||
    Number(amount) > budget;

  return (
    <div className="flex min-h-0 flex-col gap-3 lg:h-full lg:gap-4">
      {/* THE CLOCK. Its own panel, separate from the money below it. Whose
          turn it is and how long is left are one fact — the phase label
          answers "the clock is counting down on whom" — and belong together;
          what winning would cost is a different fact, and stacking both in
          one box read as more related than they are.

          The panel itself carries clockTone: a cream tint says the turn is
          yours, red says whoever it belongs to is about to lose it, and both
          are read off the same variable the digits and bar already used, so
          the four cues never disagree with each other. */}
      <div
        className={`shrink-0 rounded border p-3.5 transition-colors lg:p-4 ${
          clockTone === "urgent"
            ? "border-hidden-text/60 bg-hidden-text/10"
            : clockTone === "mine"
              ? "border-panel/60 bg-panel/10"
              : "border-line bg-surface-raised"
        }`}
      >
        {/* Promoted from a 10px mono kicker — identical to every label on
            this screen — to the second-biggest thing in the panel. "Whose
            turn" is the first question this column answers and it was
            previously the smallest text on it. */}
        <span
          className={`font-slab text-xl leading-none -skew-x-7 uppercase ${
            clockTone === "urgent"
              ? "text-hidden-text"
              : clockTone === "mine"
                ? "text-fg"
                : "text-fg-muted"
          }`}
        >
          {phase === "lot_preview"
            ? "Bidding has not started"
            : phase === "sold"
              ? "Sold"
              : isMine
                ? "Your turn"
                : `${onClock?.display_name ?? "Someone"} is deciding`}
        </span>

        {/* Slab digits, the size the price used to have — this is the number
            the column leads with. The countdown runs to 9.5s against a real
            10s deadline, so a bid sent as the bar empties still has half a
            second of real deadline behind it. The slack sits behind the clock
            rather than in front of it, which is what keeps zero meaning zero. */}
        <p className="mt-3 font-mono text-[10px] tracking-[0.15em] text-fg-muted uppercase">
          Time left
        </p>
        <p
          className={`mt-1.5 font-slab text-4xl leading-none -skew-x-7 tabular-nums lg:text-5xl ${urgent ? "text-hidden-text" : "text-fg"}`}
        >
          {formatClock(seconds)}
        </p>
        <div
          role="timer"
          aria-label={seconds === null ? "No timer" : `${seconds} seconds left`}
          className="mt-2.5 h-1.5 w-full overflow-hidden rounded-full bg-panel/15"
        >
          <div
            className={`h-full ${urgent ? "bg-hidden-text" : "bg-fg"}`}
            style={{
              width: `${fraction * 100}%`,
              transition: `width ${TICK_MS}ms linear`,
            }}
          />
        </div>
      </div>

      {/* THE BID. Everything that costs money or spends a chance — price,
          raises, Pass — together in a panel of its own. Its status line
          already says "Waiting on another player" when it isn't your turn
          (see BLOCKED_TEXT), so nothing here depended on the phase label
          living in the same box. */}
      <div
        ref={surface}
        tabIndex={-1}
        className="relative flex min-h-0 flex-1 flex-col gap-3 rounded border border-line bg-surface-raised p-3.5 outline-none lg:gap-4 lg:p-4"
      >
        {/* The price. Slab, matching the clock digit next door — the two
            panels are a set now, and a plain bold number here read as the
            junior fact next to the clock's full treatment when it is, after
            time, the second most important number on the screen. Budget
            drops to its own caption line rather than riding the baseline: at
            this size "$2 $14 left" on one line would read as one quantity. */}
        <div>
          <p className="font-mono text-[10px] tracking-[0.15em] text-fg-muted uppercase">
            Standing bid
          </p>
          <p className="mt-1.5 font-slab text-4xl leading-none -skew-x-7 tabular-nums lg:text-5xl">
            {phase === "lot_preview" ? "—" : `$${price}`}
          </p>
          <p className="mt-1.5 font-mono text-[11px] text-fg-muted tabular-nums">
            ${budget} left
          </p>
        </div>

        {/* Raises are one row of equals — they are the same move at different
            sizes, and a column would imply an order between them. */}
        <div className="flex gap-2">
          {INCREMENTS.map((increment) => (
            <Button
              key={increment}
              type="button"
              disabled={!actionable || !canAfford(price, budget, increment)}
              onClick={() => onRaise(price + increment)}
            >
              +${increment}
            </Button>
          ))}
          <Button
            ref={customButton}
            type="button"
            disabled={!actionable}
            onClick={() => {
              setAmount(String(minimum));
              setCustomFor(interactionKey);
            }}
          >
            Custom
          </Button>
        </div>
        <p
          role={error ? "alert" : undefined}
          className={`min-h-5 text-xs leading-5 ${error ? "text-hidden-text" : "text-fg-muted"}`}
        >
          {error ??
            (phase === "lot_preview"
              ? "This player enters the auction."
              : phase === "sold"
                ? "The next player is coming up."
                : blocked
                  ? BLOCKED_TEXT[blocked]
                  : !canAfford(price, budget, INCREMENTS[1])
                    ? `You can only raise by $${INCREMENTS[0]}.`
                    : `A win fills your open ${slot}.`)}
        </p>

        {/* Pass is permanent — it drops you from this lot for the rest of it —
            so it gets the weight of a real control rather than a 12px link
            floated into a sentence. It is set apart below the rule and pinned
            to the foot of the panel, far enough from the raises that a thumb
            going for +$1 at three seconds left cannot land on it, and it
            holds its place disabled so nothing under it moves when your turn
            comes round.

            Ghost rather than solid: there is one primary action per view and
            that is the raise. */}
        <div className="mt-auto border-t border-line pt-3">
          <Button
            type="button"
            variant="ghost"
            disabled={phase !== "bidding_self" || pending}
            onClick={onPass}
          >
            Pass
          </Button>
        </div>
        {custom && (
          <form
            role="dialog"
            aria-label="Custom bid"
            className="absolute right-3 bottom-3 left-3 rounded-card bg-panel p-3 text-panel-fg shadow-card"
            onSubmit={(event) => {
              event.preventDefault();
              if (!invalid) onRaise(Number(amount));
            }}
            onKeyDown={(event) => {
              if (event.key === "Escape") {
                event.preventDefault();
                closeCustom();
              }
            }}
          >
            <label className="block font-mono text-[10px] tracking-[.13em] text-panel-muted uppercase">
              Custom bid
              <input
                ref={input}
                value={amount}
                onChange={(event) => setAmount(event.target.value)}
                type="number"
                min={minimum}
                max={budget}
                step="1"
                inputMode="numeric"
                className="mt-2 block w-full rounded border border-panel-muted bg-[#fffdf7] px-2 py-2 font-mono text-lg font-bold"
              />
            </label>
            <p className="mt-1 text-xs text-panel-muted">
              Minimum is ${minimum}. Your maximum is ${budget}.
            </p>
            <div className="mt-2 flex gap-2">
              <Button
                type="submit"
                variant="ink"
                fullWidth={false}
                disabled={invalid || pending}
              >
                Bid ${amount}
              </Button>
              <button
                type="button"
                onClick={closeCustom}
                className="text-xs text-panel-muted underline"
              >
                Cancel
              </button>
            </div>
          </form>
        )}
      </div>
    </div>
  );
}

/** Names a winner, so the game ends rather than merely stopping. */
function FinalScreen({
  lots,
  players,
  standings,
  viewerId,
  roomCode,
}: {
  lots: Lot[];
  players: Player[];
  standings: Standing[];
  viewerId: string;
  roomCode: string | null;
}) {
  const ranked = byPlacement(standings);
  const nameOf = (userId: string) =>
    players.find((p) => p.user_id === userId)?.display_name ?? "Unknown player";
  const winners = ranked.filter((s) => s.placement === 1);

  return (
    <>
      <header className="flex flex-col gap-2 pt-4">
        <p className="font-mono text-[10px] tracking-[0.15em] text-fg-muted uppercase">
          Final
        </p>
        <h1 className="font-slab text-3xl leading-none -skew-x-7 uppercase">
          {winners.length === 0
            ? "Game over"
            : winners.length === 1
              ? `${nameOf(winners[0].user_id)} wins`
              : `${winners.map((w) => nameOf(w.user_id)).join(" & ")} tie`}
        </h1>
      </header>

      <ul className="flex flex-col gap-2.5">
        {ranked.map((standing) => (
          <li key={standing.user_id}>
            <Card edge={false}>
              <div className="flex items-baseline justify-between gap-3 px-3 pt-2.5 pb-1">
                <span className="font-slab text-xl leading-none -skew-x-7 uppercase">
                  <span className="mr-2 font-mono text-[11px] text-panel-muted tabular-nums">
                    {standing.placement}
                  </span>
                  {nameOf(standing.user_id)}
                  {standing.user_id === viewerId ? (
                    <span className="ml-1.5 font-mono text-[9px] tracking-[0.13em] text-panel-muted">
                      YOU
                    </span>
                  ) : null}
                </span>
                <span className="font-mono text-sm font-bold text-panel-fg tabular-nums">
                  {fmt(standing.raw_score)}
                </span>
              </div>
              <div className="px-3 pb-3">
                <RosterFinal lots={lots} userId={standing.user_id} />
              </div>
            </Card>
          </li>
        ))}
      </ul>

      <Link
        href={roomCode ? `/lobby/${roomCode}` : "/"}
        className="mt-2 text-sm text-fg-muted underline decoration-line underline-offset-4 transition-colors hover:text-fg hover:decoration-fg"
      >
        {roomCode ? "Back to the room" : "Back home"}
      </Link>
    </>
  );
}

/** The full roster, so there is something to argue about afterwards. */
function RosterFinal({ lots, userId }: { lots: Lot[]; userId: string }) {
  const won = lots.filter((l) => l.winner_id === userId);

  return (
    <dl className="flex flex-col gap-1 border-t border-dashed border-[#c7bfac] pt-2 font-mono text-[10px] text-panel-muted">
      {SLOTS.map((slot) => {
        const lot = won.find((l) => l.slot === slot) ?? null;
        return (
          <div key={slot} className="flex items-baseline justify-between gap-2">
            <dt className="w-10 shrink-0 uppercase">{slot}</dt>
            <dd className="flex-1 truncate text-panel-fg">
              {lot ? `${lot.display_name} · ${lot.season} wk ${lot.week}` : "—"}
            </dd>
            <dd className="shrink-0 font-bold text-panel-fg tabular-nums">
              {lot ? `$${lot.price} · ${fmt(lot.points)}` : ""}
            </dd>
          </div>
        );
      })}
    </dl>
  );
}

/** Points arrive as numeric strings; one decimal is how the game reads them. */
function fmt(value: string | number | null): string {
  if (value === null) return "—";
  return Number(value).toFixed(1);
}

/** mm:ss, even though no phase in this game is long enough to ever clear a
 *  minute — it is the shape a countdown reads as at a glance, not a label. */
function formatClock(seconds: number | null): string {
  if (seconds === null) return "—:—";
  const m = Math.floor(seconds / 60);
  const s = seconds % 60;
  return `${m}:${String(s).padStart(2, "0")}`;
}
