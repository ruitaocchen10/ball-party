/** The public projection returned by wavelength.state(). */
export type Board = {
  matchId: string;
  mode: "coop" | "versus";
  preset: "short" | "medium" | "long" | null;
  roundCount: number;
  currentRound: number;
  phase: "fill" | "guess" | "reveal" | "complete";
  phaseDeadline: string | null;
  serverNow: string;
  teamScores: number[];
};

export type WavelengthPlayer = {
  match_id: string;
  user_id: string;
  seat: number;
  team: number;
  absent: boolean;
  last_seen_at: string;
  display_name: string;
  avatar_url: string | null;
};

export type WavelengthRound = {
  match_id: string;
  round: number;
  psychic_id: string;
  guesser_id: string;
  status: "pending" | "open" | "locked" | "skipped";
  points: number | null;
  /** Present only after the server has locked or skipped the round. */
  revealed_target: number | null;
  /** Where the guess was locked; null until locked (and for skipped rounds). */
  guess_position: number | null;
};

export type Card = { match_id: string; round: number; card_id: number; left_label: string; right_label: string };
export type Clue = { match_id: string; round: number; clue: string };
export type ClueStatus = { match_id: string; round: number };
export type Target = { match_id: string; round: number; target: number };

/** Where a point on the 0..1000 scale sits on the dial's semicircle (viewBox 1000x530, pivot at 500,260). */
export const DIAL = { cx: 500, cy: 260, radius: 470 } as const;
export function dialPoint(position: number, radius: number = DIAL.radius): { x: number; y: number } {
  const angle = Math.PI * (1 - position / 1000);
  return { x: DIAL.cx + radius * Math.cos(angle), y: DIAL.cy - radius * Math.sin(angle) };
}
/** The inverse: the scale position a pointer at viewBox (x, y) is aiming at. */
export function dialPosition(x: number, y: number): number {
  const angle = Math.atan2(DIAL.cy - y, x - DIAL.cx);
  // Below the baseline the angle goes negative; snap to the nearer end of the dial.
  const above = angle >= 0 ? angle : x < DIAL.cx ? Math.PI : 0;
  return Math.round((1 - above / Math.PI) * 1000);
}

/** The durable terminal projection. It is deliberately separate from Board:
 * scores keep moving during play, while this row is written exactly once. */
export type WavelengthResult = {
  match_id: string;
  mode: "coop" | "versus";
  preset: "short" | "medium" | "long" | null;
  outcome: "win" | "lose" | "team_0_win" | "team_1_win";
  score: number;
  bullseyes: number;
  stars: 0 | 1 | 2 | 3 | null;
};

type StateRow = {
  match_id?: unknown; mode?: unknown; preset?: unknown; round_count?: unknown;
  current_round?: unknown; phase?: unknown; phase_deadline?: unknown; server_now?: unknown; team_scores?: unknown;
};

/** Parse the nullable Postgres composite rather than letting incomplete state
 * quietly turn into a playable-looking board. */
export function boardFromState(row: unknown): Board | null {
  if (!row || typeof row !== "object") return null;
  const value = row as StateRow;
  if (
    typeof value.match_id !== "string" ||
    (value.mode !== "coop" && value.mode !== "versus") ||
    (value.preset !== null && value.preset !== "short" && value.preset !== "medium" && value.preset !== "long") ||
    !Number.isInteger(value.round_count) || !Number.isInteger(value.current_round) ||
    (value.phase !== "fill" && value.phase !== "guess" && value.phase !== "reveal" && value.phase !== "complete") ||
    (value.phase_deadline !== null && typeof value.phase_deadline !== "string") ||
    typeof value.server_now !== "string" ||
    !Array.isArray(value.team_scores) || !value.team_scores.every((score): score is number => typeof score === "number" && Number.isFinite(score))
  ) return null;
  return {
    matchId: value.match_id, mode: value.mode, preset: value.preset,
    roundCount: value.round_count as number, currentRound: value.current_round as number,
    phase: value.phase, phaseDeadline: value.phase_deadline, serverNow: value.server_now,
    teamScores: value.team_scores as number[],
  };
}

export const CLUE_MAX_CHARS = 100;
export const CLUE_MAX_WORDS = 8;

export function validateClue(raw: string): string | null {
  const clue = raw.trim();
  if (!clue) return "Write a clue before locking it in.";
  if (/\d/.test(clue)) return "Clues cannot contain digits.";
  if (clue.length > CLUE_MAX_CHARS) return `Keep your clue to ${CLUE_MAX_CHARS} characters or fewer.`;
  if (clue.split(/\s+/).length > CLUE_MAX_WORDS) return `Keep your clue to ${CLUE_MAX_WORDS} words or fewer.`;
  return null;
}

export type Wedge = { points: 2 | 3 | 4; from: number; to: number };

/** Five symmetric scoring bands around a server-revealed target. */
export function scoringWedges(target: number, width = 40, scaleMax = 1000): Wedge[] {
  const half = width / 2;
  const wedges: Wedge[] = [
    { points: 2, from: target - half * 5, to: target - half * 3 },
    { points: 3, from: target - half * 3, to: target - half },
    { points: 4, from: target - half, to: target + half },
    { points: 3, from: target + half, to: target + half * 3 },
    { points: 2, from: target + half * 3, to: target + half * 5 },
  ];
  return wedges.map((wedge) => ({ ...wedge, from: Math.max(0, wedge.from), to: Math.min(scaleMax, wedge.to) }));
}

export function scoreAt(position: number, target: number, width = 40): 0 | 2 | 3 | 4 {
  const distance = Math.abs(position - target);
  if (distance <= width / 2) return 4;
  if (distance <= width * 3 / 2) return 3;
  return distance <= width * 5 / 2 ? 2 : 0;
}
