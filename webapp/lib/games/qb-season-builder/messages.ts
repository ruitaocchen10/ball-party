/**
 * The game API raises short machine-readable strings — see the error tables in
 * docs/games/qb_season_builder.md. The message is the contract with the
 * client; this is where each becomes a sentence. Anything absent from the map
 * is a bug rather than a player-facing condition, so it surfaces raw instead of
 * being flattened into a friendly lie.
 */
export const QB_MESSAGES: Record<string, string> = {
  not_authenticated: "Sign in first.",
  not_a_participant: "This run isn't yours.",
  match_not_found: "This run no longer exists.",
  match_not_playing: "This run has already ended.",
  slot_filled: "That slot is already filled.",
  source_not_on_spin: "That option isn't on this spin any more.",
  respin_used: "You've already used your respin.",
  draft_complete: "All six slots are filled.",
  draft_incomplete: "Fill all six slots first.",
  pool_exhausted: "Couldn't deal a spin. Try again.",
};

export function qbErrorMessage(message: string): string {
  return QB_MESSAGES[message] ?? message;
}
