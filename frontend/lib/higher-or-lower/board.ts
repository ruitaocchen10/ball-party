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

/** The platform's per-match standings row — the shape #28 writes into. */
export type Standing = Database["public"]["Tables"]["match_players"]["Row"];

/** A dealt match's format snapshot, loaded once beside the ladder. */
export type Board = {
  questionCount: number;
  currentQuestion: number;
  scoringMode: string;
  seasonFrom: number;
  seasonTo: number;
  phase: "board_intro" | "call" | "reveal" | "sudden_death_call" | "sudden_death_reveal" | "complete";
  phaseDeadline: string | null;
  serverNow: string;
};

/**
 * Standard competition ranking, read back for display. The auction's board
 * module says almost the same function; they stay apart on purpose (see the
 * note on cardIdentityLine below), so this is the one place this game defines
 * "what order does the final scoreboard read in".
 */
export function byPlacement(standings: Standing[]): Standing[] {
  return [...standings].sort(
    (a, b) => (a.placement ?? 99) - (b.placement ?? 99) || Number(b.raw_score) - Number(a.raw_score),
  );
}

/** Sudden death is two phases, everywhere a caller only needs "is it live". */
export function isSuddenDeath(phase: Board["phase"]): boolean {
  return phase === "sudden_death_call" || phase === "sudden_death_reveal";
}

/** Which sudden-death round is live — the spare ordinals start where the
 * twelve questions end, so the round number is just the distance past them. */
export function suddenDeathRound(board: Board): number {
  return board.currentQuestion - board.questionCount;
}

/**
 * Whether this viewer's two buttons should be live right now. The server is
 * the actual rule (higher_or_lower.call rejects anything this disagrees
 * with) — this only decides what the controls show, the same division the
 * auction's disabled-bid derivation draws.
 */
export function canCallNow(board: Board, viewer: Player | undefined): boolean {
  if (!viewer) return false;
  if (board.phase === "call") return true;
  if (board.phase === "sudden_death_call") return viewer.sudden_death && viewer.eliminated_at === null;
  return false;
}

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
