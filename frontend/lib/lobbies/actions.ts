"use server";

import { redirect } from "next/navigation";
import { revalidatePath } from "next/cache";

import { GAMES } from "@/lib/games/catalog";
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
  not_host: "Only the host can close the room.",
  not_authenticated: "Sign in first.",
  code_generation_failed: "Couldn't find a free room code. Try again.",
};

function withError(path: string, error: { message: string }): string {
  const text = MESSAGES[error.message] ?? error.message;
  return `${path}?error=${encodeURIComponent(text)}`;
}

function normalizeCode(value: FormDataEntryValue | null): string {
  return String(value ?? "").trim().toUpperCase();
}

/**
 * A room, optionally opened with a game in mind.
 *
 * The slug rides along in the URL rather than in a column because a lobby has
 * no mode — the game is chosen per run, from inside the room (see
 * docs/architecture/lobbies). So this is a note to the person who clicked,
 * carried as far as the room and no further: it is not shared with the other
 * players, and it is gone the moment they navigate away. When runs are built
 * the choice becomes a row on `runs` and this hint goes away.
 *
 * Unrecognised slugs are dropped rather than echoed — the room URL is a thing
 * people paste to each other, so nothing arbitrary gets to ride in it.
 */
export async function createLobby(formData?: FormData) {
  const slug = String(formData?.get("game") ?? "");
  const game = GAMES.find((g) => g.slug === slug && g.status === "live");

  const supabase = await createClient();
  const { data, error } = await supabase.rpc("create_lobby");

  // redirect() unwinds by throwing, so it must never sit inside a try/catch.
  if (error) redirect(withError("/", error));

  revalidatePath("/", "layout");
  redirect(game ? `/lobby/${data.code}?game=${game.slug}` : `/lobby/${data.code}`);
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
