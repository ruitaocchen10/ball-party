/**
 * Each mode's roster slots, one per round, in the order
 * `sabotage_draft_private.mode_slots` (see
 * supabase/migrations/20260926100000_0157_sabotage_draft_modes.sql) deals
 * them into `sabotage_draft_rounds.slot`. The last round of every mode is
 * the X-Factor: it has no single slot of its own, its eligible pick set is
 * any offensive skill position, and the drafter chooses at pick time which
 * existing skill slot it upgrades (see `X_FACTOR` below).
 *
 * Safe to hardcode client-side rather than read off the row: the ordering is
 * a rule of the game, not per-match data, the same way the auction's
 * increments are a constant rather than a fetched value.
 */
export const GAME_MODES = ["full", "standard", "quick"] as const;
export type GameMode = (typeof GAME_MODES)[number];

export const MODE_SLOTS: Record<GameMode, readonly string[]> = {
  full: ["QB", "RB1", "RB2", "WR1", "WR2", "WR3", "TE", "OL", "DL", "LB", "CB", "S", "ST", "X_FACTOR"],
  standard: ["QB", "RB1", "RB2", "WR1", "WR2", "TE", "FLEX", "DEF", "ST", "X_FACTOR"],
  quick: ["QB", "RB1", "WR1", "TE", "FLEX", "DEF", "X_FACTOR"],
};

export const MODE_LABELS: Record<GameMode, { name: string; blurb: string }> = {
  full: { name: "Full", blurb: "14 rounds · every position, offense through special teams" },
  standard: { name: "Standard", blurb: "10 rounds · skill positions, a defender and special teams" },
  quick: { name: "Quick", blurb: "7 rounds · skill positions and a defender" },
};

export function isGameMode(value: unknown): value is GameMode {
  return typeof value === "string" && (GAME_MODES as readonly string[]).includes(value);
}

/**
 * The board only carries `round_count`, and each mode has a distinct one, so
 * the mode is recoverable from it without widening the server's round type.
 * Anything unrecognized reads as the original full game.
 */
export function modeForRoundCount(roundCount: number): GameMode {
  return GAME_MODES.find(mode => MODE_SLOTS[mode].length === roundCount) ?? "full";
}

/** Slot for a round, defaulting to the full game's order. Past the last round falls to X_FACTOR. */
export function slotForRound(round: number, roundCount = MODE_SLOTS.full.length): string {
  const slots = MODE_SLOTS[modeForRoundCount(roundCount)];
  return slots[round - 1] ?? "X_FACTOR";
}

/** The round the X-Factor is dealt in: always the match's last. */
export function xFactorRound(roundCount: number): number {
  return roundCount;
}

/** The roster slots a mode drafts directly: every round but the X-Factor. */
export function rosterSlots(roundCount: number): readonly string[] {
  return MODE_SLOTS[modeForRoundCount(roundCount)].slice(0, -1);
}

/** Offensive skill slots an X-Factor can upgrade, which is every one a mode has of these. */
const SKILL_SLOTS = new Set(["QB", "RB1", "RB2", "WR1", "WR2", "WR3", "TE", "FLEX"]);

/**
 * The slots an X-Factor of this position category may replace in this mode.
 * Mirrors `submit_x_factor_decision`'s own validation: the slot has to exist
 * in the mode and match the category (FLEX takes an RB, WR or TE).
 */
export function xFactorTargets(category: string | undefined, roundCount: number): string[] {
  if (!category) return [];
  return rosterSlots(roundCount).filter(slot => {
    if (!SKILL_SLOTS.has(slot)) return false;
    if (slot === "FLEX") return category === "RB" || category === "WR" || category === "TE";
    return slot.replace(/[0-9]/g, "") === category;
  });
}

/** What a slot is called where there is room to spell it out. */
export function slotLabel(slot: string): string {
  if (slot === "DEF") return "Defensive Player";
  return slot.replace("_", " ");
}

/** The "choosing …" line for a round: what the drafter may take from their spin. */
export function chooseLabel(slot: string): string {
  if (slot === "X_FACTOR") return "any offensive skill player";
  if (slot === "FLEX") return "an RB, WR or TE";
  if (slot === "DEF") return "a defensive player";
  return `a ${slot.replace(/[0-9]/g, "")}`;
}
