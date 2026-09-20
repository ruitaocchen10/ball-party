import type { Database } from "@/lib/supabase/database.types";

/**
 * A run, as the server hands it over.
 *
 * `qb_season_builder.state`, `pick` and `respin` all answer with the same
 * `board` row, and this is that row parsed into something the screen can use
 * without re-checking it: the jsonb `options` and `picks` arrive untyped, and
 * every number in them is null in a hidden run until it is finished. Whether a
 * value shows is therefore never decided here or on the screen — a value is
 * shown when the server sent one. See docs/games/qb_season_builder.md.
 *
 * Deliberately thin, like the other games' board modules: what little logic
 * there is (parsing the row, finding a slot's pick) is asserted through the
 * match screen's suite rather than through a seam that would exist only to be
 * tested.
 */

export type BoardRow = Database["qb_season_builder"]["CompositeTypes"]["board"];

export const SLOTS = ["accuracy", "arm_talent", "mobility", "iq", "build", "supporting_cast"] as const;
export type Slot = (typeof SLOTS)[number];

/** The five things a quarterback is rated on; the sixth slot is the team. */
export const QUALITIES = ["accuracy", "arm_talent", "mobility", "iq", "build"] as const;
export type Quality = (typeof QUALITIES)[number];

export const SLOT_LABELS: Record<Slot, string> = {
  accuracy: "Accuracy",
  arm_talent: "Arm Talent",
  mobility: "Mobility",
  iq: "IQ",
  build: "Build",
  supporting_cast: "Supporting Cast",
};

export type Quarterback = {
  playerId: string;
  displayName: string;
  /** Null when the run is hidden and not yet finished. */
  values: Record<Quality, number> | null;
};

export type Spin = {
  franchiseCode: string;
  season: number;
  quarterbacks: Quarterback[];
  /** The team's Supporting Cast value; null when hidden. */
  supportingCast: number | null;
};

export type DraftPick = {
  round: number;
  slot: Slot;
  franchiseCode: string;
  season: number;
  /** Null for the Supporting Cast, whose source is the team. */
  playerId: string | null;
  displayName: string | null;
  value: number | null;
};

export type Board = {
  matchId: string;
  mode: "visible" | "hidden";
  /** `picking` while a round is open; `ready_to_finish` once all six slots are filled. */
  phase: "picking" | "ready_to_finish" | "complete";
  roundCount: number;
  currentRound: number;
  respinUsed: boolean;
  /** The current round's spin; null once no round is open. */
  spin: Spin | null;
  picks: DraftPick[];
};

/**
 * The board, or null when the row is not one a screen can draw — a missing
 * field, an unknown mode or phase, a spin with no options. The caller treats
 * that the way every other match screen treats a state it cannot read.
 */
export function boardFromRow(row: Partial<BoardRow> | null | undefined): Board | null {
  if (!row || row.match_id == null || row.round_count == null || row.current_round == null || row.respin_used == null) {
    return null;
  }
  if (row.mode !== "visible" && row.mode !== "hidden") return null;
  if (row.phase !== "picking" && row.phase !== "ready_to_finish" && row.phase !== "complete") return null;

  const picks = picksFromJson(row.picks);
  if (picks === null) return null;

  let spin: Spin | null = null;
  if (row.franchise_code != null && row.season != null) {
    const options = optionsFromJson(row.options);
    if (options === null) return null;
    spin = { franchiseCode: row.franchise_code, season: row.season, ...options };
  }

  return {
    matchId: row.match_id,
    mode: row.mode,
    phase: row.phase,
    roundCount: row.round_count,
    currentRound: row.current_round,
    respinUsed: row.respin_used,
    spin,
    picks,
  };
}

export function pickForSlot(board: Board, slot: Slot): DraftPick | null {
  return board.picks.find((pick) => pick.slot === slot) ?? null;
}

type JsonObject = { [key: string]: unknown };

function isObject(value: unknown): value is JsonObject {
  return typeof value === "object" && value !== null && !Array.isArray(value);
}

function numberOrNull(value: unknown): number | null {
  return typeof value === "number" ? value : null;
}

function optionsFromJson(json: unknown): Pick<Spin, "quarterbacks" | "supportingCast"> | null {
  if (!isObject(json) || !Array.isArray(json.quarterbacks) || !isObject(json.supporting_cast)) return null;

  const quarterbacks: Quarterback[] = [];
  for (const raw of json.quarterbacks) {
    if (!isObject(raw) || typeof raw.player_id !== "string" || typeof raw.display_name !== "string") return null;
    quarterbacks.push({
      playerId: raw.player_id,
      displayName: raw.display_name,
      values: qualityValues(raw.values),
    });
  }
  return { quarterbacks, supportingCast: numberOrNull(json.supporting_cast.value) };
}

function qualityValues(json: unknown): Record<Quality, number> | null {
  if (!isObject(json)) return null;
  const values = {} as Record<Quality, number>;
  for (const quality of QUALITIES) {
    const value = numberOrNull(json[quality]);
    if (value === null) return null;
    values[quality] = value;
  }
  return values;
}

function picksFromJson(json: unknown): DraftPick[] | null {
  if (!Array.isArray(json)) return null;
  const picks: DraftPick[] = [];
  for (const raw of json) {
    if (
      !isObject(raw) || typeof raw.round !== "number" || typeof raw.slot !== "string" ||
      !(SLOTS as readonly string[]).includes(raw.slot) ||
      typeof raw.franchise_code !== "string" || typeof raw.season !== "number"
    ) return null;
    picks.push({
      round: raw.round,
      slot: raw.slot as Slot,
      franchiseCode: raw.franchise_code,
      season: raw.season,
      playerId: typeof raw.player_id === "string" ? raw.player_id : null,
      displayName: typeof raw.display_name === "string" ? raw.display_name : null,
      value: numberOrNull(raw.value),
    });
  }
  return picks;
}
