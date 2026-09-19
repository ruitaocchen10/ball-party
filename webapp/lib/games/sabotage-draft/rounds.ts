/**
 * Round 1-13's roster slot is fixed by round number, not dealt or chosen —
 * `sabotage_draft_private.deal_board` (see
 * supabase/migrations/20260824014211_0059_sabotage_draft_player_spins.sql)
 * walks this exact array in this exact order when it writes
 * `sabotage_draft_rounds.slot`, and the design doc lists the same order.
 * Round 14 has no single slot; its eligible pick set is any offensive skill
 * position, decided by the drafter at pick time (see `X_FACTOR` below).
 *
 * Safe to hardcode client-side rather than read off the row: this ordering
 * is a rule of the game, not per-match data, the same way the auction's
 * increments are a constant rather than a fetched value.
 */
export const ROUND_SLOTS = [
  "QB", "RB1", "RB2", "WR1", "WR2", "WR3", "TE",
  "OL", "DL", "LB", "CB", "S", "ST",
] as const;

export const X_FACTOR_ROUND = 14;

/** Falls back to X_FACTOR past round 13, mirroring the deal loop's own `case`. */
export function slotForRound(round: number): string {
  return round <= ROUND_SLOTS.length ? ROUND_SLOTS[round - 1] : "X_FACTOR";
}
