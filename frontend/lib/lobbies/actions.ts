"use server";

import { redirect } from "next/navigation";
import { revalidatePath } from "next/cache";

import { createClient } from "@/lib/supabase/server";

/**
 * The lobby RPCs raise short machine-readable strings — see
 * supabase/migrations/20260806200858_0005_lobby_rpc.sql. Anything absent from
 * this map is a bug rather than a player-facing condition, so it surfaces raw
 * instead of being flattened into a friendly lie.
 */
const MESSAGES: Record<string, string> = {
  lobby_not_found: "No room with that code.",
  lobby_full: "That room is already full.",
  not_a_member: "You're not in that room.",
  not_host: "Only the host can start or close the game.",
  not_authenticated: "Sign in first.",
  code_generation_failed: "Couldn't find a free room code. Try again.",
  lobby_closed: "This room has closed.",
  bad_player_count: "You need between two and four players.",
  mode_not_supported: "Party mode isn't ready yet.",
  run_already_active: "A game is already running in this room.",
  too_few_players: "Not enough players to deal a board.",
  pool_exhausted: "Couldn't deal a full board. Try again.",
};

function withError(path: string, error: { message: string }): string {
  const text = MESSAGES[error.message] ?? error.message;
  return `${path}?error=${encodeURIComponent(text)}`;
}

function normalizeCode(value: FormDataEntryValue | null): string {
  return String(value ?? "").trim().toUpperCase();
}

/**
 * A room.
 *
 * The game tile that opened it used to pass its slug along in the URL as a note
 * to the person who clicked. That hint is gone: the choice is now a column on
 * `runs`, written when the host starts the game from inside the room, which is
 * where a lobby with no mode of its own was always going to have to make it.
 */
export async function createLobby() {
  const supabase = await createClient();
  const { data, error } = await supabase.rpc("create_lobby");

  // redirect() unwinds by throwing, so it must never sit inside a try/catch.
  if (error) redirect(withError("/", error));

  revalidatePath("/", "layout");
  redirect(`/lobby/${data.code}`);
}

/**
 * Turn the room into a game.
 *
 * Two calls, because the platform does not dispatch into a game's setup — it
 * does not know games exist. `start_run` freezes the roster and opens a match
 * in `setup`; the game's own RPC deals into it and moves it to `playing`. See
 * docs/architecture/architecture.md for why that seam is where it is.
 *
 * The dispatch below is hardcoded to the one game that is built. It belongs on
 * the catalog the moment there are two.
 */
export async function startRun(formData: FormData) {
  const lobbyId = String(formData.get("lobby_id") ?? "");
  const code = normalizeCode(formData.get("code"));
  const supabase = await createClient();

  const { data: match, error } = await supabase.rpc("start_run", {
    p_lobby_id: lobbyId,
    p_mode: "arcade",
    p_game: "auction_team_builder",
  });
  if (error) redirect(withError(`/lobby/${code}`, error));

  const { error: dealError } = await supabase.rpc("start_auction", { p_match_id: match.id });
  if (dealError) redirect(withError(`/lobby/${code}`, dealError));

  revalidatePath("/", "layout");
  redirect(`/match/${match.id}`);
}

/**
 * Join by code is two steps on purpose: this only navigates. The room page
 * decides whether you need to join, which means a pasted invite link and a
 * typed code land on exactly the same path.
 */
export async function goToLobby(formData: FormData) {
  const code = normalizeCode(formData.get("code"));
  if (!code) redirect(`/?error=${encodeURIComponent("Enter a room code.")}`);
  redirect(`/lobby/${code}`);
}

export async function joinLobby(formData: FormData) {
  const code = normalizeCode(formData.get("code"));
  const supabase = await createClient();

  let result = await supabase.rpc("join_lobby", { p_code: code });

  // Two players swapping rooms at the same instant take the lobby locks in
  // opposite order. Postgres kills one of them; retrying immediately is safe
  // because join_lobby is idempotent for a player already in the room.
  if (result.error?.code === "40P01") {
    result = await supabase.rpc("join_lobby", { p_code: code });
  }

  if (result.error) redirect(withError(`/lobby/${code}`, result.error));

  revalidatePath("/", "layout");
  redirect(`/lobby/${code}`);
}

export async function leaveLobby(formData: FormData) {
  const lobbyId = String(formData.get("lobby_id") ?? "");
  const supabase = await createClient();

  const { error } = await supabase.rpc("leave_lobby", { p_lobby_id: lobbyId });
  if (error) redirect(withError("/", error));

  revalidatePath("/", "layout");
  redirect("/");
}

export async function closeLobby(formData: FormData) {
  const lobbyId = String(formData.get("lobby_id") ?? "");
  const code = normalizeCode(formData.get("code"));
  const supabase = await createClient();

  const { error } = await supabase.rpc("close_lobby", { p_lobby_id: lobbyId });
  if (error) redirect(withError(`/lobby/${code}`, error));

  revalidatePath("/", "layout");
  redirect("/");
}
