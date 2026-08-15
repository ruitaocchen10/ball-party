import type { Database } from "@/lib/supabase/database.types";

/**
 * The ladder, as the server hands it over.
 *
 * Deliberately thin. The auction has a derivation module with its own unit
 * tests because a disabled bid button has to explain which of several rules
 * blocked it; this game's derivation is "which two cards is the table looking
 * at", so what little there is lives here and is asserted through the match
 * screen's suite rather than through a seam that would exist only to be tested.
 */

export type Card = Database["public"]["Tables"]["higher_or_lower_cards"]["Row"];
export type Seat = Database["public"]["Tables"]["higher_or_lower_players"]["Row"];
export type Call = Database["public"]["Tables"]["higher_or_lower_calls"]["Row"];
export type CallStatus = Database["public"]["Tables"]["higher_or_lower_call_statuses"]["Row"];

export type Player = Seat & { display_name: string };

/** A dealt match's format snapshot, loaded once beside the ladder. */
export type Board = {
  questionCount: number;
  currentQuestion: number;
  scoringMode: string;
  seasonFrom: number;
  seasonTo: number;
  phase: "board_intro" | "call" | "reveal" | "complete";
  phaseDeadline: string | null;
  serverNow: string;
};

/**
 * The two cards a question puts side by side.
 *
 * Card 0 is the seed anchor, so question k compares card k against card k-1.
 * Every card past the first is both a challenger and, once it reveals, the
 * anchor for the question after it — one row, two moments — which is why this
 * is one lookup rather than two tables.
 */
export function questionPair(
  cards: Card[],
  question: number,
): { anchor: Card | null; challenger: Card | null } {
  return { anchor: cardAt(cards, question - 1), challenger: cardAt(cards, question) };
}

function cardAt(cards: Card[], ordinal: number): Card | null {
  return cards.find((card) => card.ordinal === ordinal) ?? null;
}

/**
 * The recall cues under the name. A weekly card places a specific game; a
 * season card is a whole season and has no honest week or opponent, so the row
 * carries nulls there and this is where that shape is read.
 *
 * The auction says almost the same sentence in its own module. They stay apart:
 * a game may not import another game (architecture.md), and the two will drift
 * — this one has no matchup framing to keep once weekly lands.
 */
export function cardIdentityLine(card: Card): string {
  if (card.week === null || card.opponent === null) {
    return `${card.season} · ${card.team}`;
  }
  return `${card.season} · Week ${card.week} · ${card.team} vs. ${card.opponent}`;
}

export function cardMetaLine(card: Card): string {
  return `${card.position} · ${cardIdentityLine(card)}`;
}

/** The era the ladder was dealt from, as the format line names it. */
export function eraLabel(board: Board): string {
  return `${board.seasonFrom}-${board.seasonTo}`;
}

export function scoringModeLabel(board: Board): string {
  return board.scoringMode === "season_total" ? "season total" : board.scoringMode;
}

/** Points arrive as numeric strings; one decimal is how the game reads them. */
export function formatPoints(value: string | number | null): string {
  if (value === null) return "—";
  return Number(value).toFixed(1);
}
