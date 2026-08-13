export const LOBBY_MESSAGES: Record<string, string> = {
  lobby_not_found: "No room with that code.",
  lobby_full: "That room is already full.",
  not_a_member: "You're not in that room.",
  not_host: "Only the host can start or close the game.",
  host_still_active: "The host is still connected. Try again in a moment.",
  not_authenticated: "Sign in first.",
  code_generation_failed: "Couldn't find a free room code. Try again.",
  lobby_closed: "This room has closed.",
  bad_player_count: "You need between two and four players.",
  mode_not_supported: "Party mode isn't ready yet.",
  run_already_active: "A game is already running in this room.",
  too_few_players: "Not enough players to deal a board.",
  pool_exhausted: "Couldn't deal a full board. Try again.",
  match_not_complete: "This game is still in progress.",
  post_game_choice_already_made: "The host has already chosen what’s next.",
  replay_not_supported: "This game can’t be replayed yet.",
};

export function lobbyErrorMessage(message: string) {
  return LOBBY_MESSAGES[message] ?? message;
}
