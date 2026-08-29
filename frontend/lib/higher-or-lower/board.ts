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

export type Player = Seat & { display_name: string; avatar_url: string | null };

export type LiveStanding = {
  player: Player;
  rank: number;
  tied: boolean;
};

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
 * The live rail follows the same result rule the server will apply at the
 * end: best streak first, then total correct. During sudden death the admitted
 * field owns the top positions; surviving contenders share the lead until a
 * round actually eliminates someone.
 */
export function liveStandings(players: Player[], phase: Board["phase"]): LiveStanding[] {
  const ordered = [...players].sort((a, b) => compareLivePlayers(a, b, phase));
  const keys = ordered.map((player) => liveRankKey(player, phase));
  const countByKey = new Map<string, number>();
  for (const key of keys) countByKey.set(key, (countByKey.get(key) ?? 0) + 1);
  let previousKey: string | null = null;
  let rank = 0;

  return ordered.map((player, index) => {
    const key = keys[index];
    if (key !== previousKey) rank = index + 1;
    previousKey = key;
    return { player, rank, tied: (countByKey.get(key) ?? 0) > 1 };
  });
}

function compareLivePlayers(a: Player, b: Player, phase: Board["phase"]): number {
  if (isSuddenDeath(phase)) {
    if (a.sudden_death !== b.sudden_death) return a.sudden_death ? -1 : 1;
    if (a.sudden_death && b.sudden_death) {
      const aAlive = a.eliminated_at === null;
      const bAlive = b.eliminated_at === null;
      if (aAlive !== bAlive) return aAlive ? -1 : 1;
      if (!aAlive && !bAlive && a.eliminated_at !== b.eliminated_at) {
        return (b.eliminated_at ?? 0) - (a.eliminated_at ?? 0);
      }
    }
  }
  return b.best_streak - a.best_streak || b.correct_count - a.correct_count || a.seat - b.seat;
}

function liveRankKey(player: Player, phase: Board["phase"]): string {
  if (isSuddenDeath(phase) && player.sudden_death) {
    return player.eliminated_at === null ? "sudden-death:alive" : `sudden-death:eliminated:${player.eliminated_at}`;
  }
  return `main:${player.best_streak}:${player.correct_count}`;
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
