import type { Bid, Lot, Player, Standing, Turn } from "@/lib/auction/board";
import { ALL_LOTS, BIDS, STANDINGS, VIEWER_ID, lotsThrough, playersAfter, turn } from "./fixture";

/* ─────────────────────────── the states ─────────────────────────────────────
   Each one is a whole board. `note` says what it is for, so a state nobody can
   explain gets deleted rather than quietly kept.
   ───────────────────────────────────────────────────────────────────────── */

export type Scenario = {
  id: string;
  label: string;
  note: string;
  lots: Lot[];
  players: Player[];
  bids: Bid[];
  turn: Turn;
  standings?: Standing[];
  finished?: boolean;
  /** Seconds on the clock when the state opens. null = no timer. */
  seconds: number | null;
};

/* At lot 7 the first six have resolved. Maria and Toby already hold a running
   back, so this lot is between Dev and Jules — which is what makes it a useful
   place to stand. */
const AT_7 = { lots: lotsThrough(6), players: playersAfter(6) };

export const SCENARIOS: Scenario[] = [
  {
    id: "preview",
    label: "Lot preview",
    note: "Five seconds before bidding opens. Controls are dead, the card is already readable.",
    ...AT_7,
    bids: [],
    turn: turn({ phase: "lot_preview", turnSeat: null }),
    seconds: 5,
  },
  {
    id: "your-turn",
    label: "Your turn",
    note: "The live state. Jules holds it at $2; you are on the clock with $14.",
    ...AT_7,
    bids: [BIDS.raise(7, "u-jules", 2)],
    turn: turn({ phase: "bidding", turnSeat: 2 }),
    seconds: 14,
  },
  {
    id: "their-turn",
    label: "Their turn, you hold it",
    note: "Two channels at once: you may not act, and you are winning. Both have to read.",
    ...AT_7,
    bids: [BIDS.raise(7, "u-jules", 2), BIDS.raise(7, "u-dev", 3)],
    turn: turn({ phase: "bidding", turnSeat: 4 }),
    seconds: 11,
  },
  {
    id: "sold",
    label: "Sold",
    note: "The payoff beat. The hidden number lands in the strip the weave was covering.",
    lots: lotsThrough(7),
    players: playersAfter(7),
    bids: [BIDS.raise(7, "u-jules", 2), BIDS.raise(7, "u-dev", 3), BIDS.pass(7, "u-jules")],
    turn: turn({ phase: "sold", turnSeat: null }),
    seconds: 5,
  },
  {
    id: "no-slot",
    label: "Locked out — no slot",
    note: "Lot 8 is another back and yours is filled. The buttons are off and have to say why.",
    lots: lotsThrough(7),
    players: playersAfter(7),
    bids: [],
    turn: turn({ phase: "bidding", currentLot: 8, turnSeat: 4 }),
    seconds: 17,
  },
  {
    id: "passed",
    label: "Locked out — you passed",
    note: "Passing is permanent, and it is a different sentence from the one above. Your RB is still open — that matters, because blockedReason() reports no_slot first and would mask this.",
    ...AT_7,
    bids: [BIDS.raise(7, "u-jules", 2), BIDS.pass(7, "u-dev")],
    turn: turn({ phase: "bidding", currentLot: 7, turnSeat: 4 }),
    seconds: 9,
  },
  {
    id: "broke",
    label: "Broke",
    note: "$0 left. You can still take an uncontested lot for nothing, so only the raises close.",
    lots: lotsThrough(6),
    players: playersAfter(6).map((p) => (p.user_id === VIEWER_ID ? { ...p, budget: 0 } : p)),
    bids: [BIDS.raise(7, "u-jules", 2)],
    turn: turn({ phase: "bidding", turnSeat: 2 }),
    seconds: 3,
  },
  {
    id: "final",
    label: "Final",
    note: "The board everybody crowds around. Toby 157.6, you 148.6.",
    lots: ALL_LOTS,
    players: playersAfter(20),
    bids: [],
    turn: turn({ currentLot: 20, phase: "sold", turnSeat: null }),
    standings: STANDINGS,
    finished: true,
    seconds: null,
  },
];
