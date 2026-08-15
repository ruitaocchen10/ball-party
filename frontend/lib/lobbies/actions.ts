"use server";

import { redirect } from "next/navigation";
import { revalidatePath } from "next/cache";

import { createClient } from "@/lib/supabase/server";
import { canCreateLobby, isGuestViewer, isSignedInViewer } from "@/lib/auth/viewer";
import { guestSessionFinishedHref } from "@/lib/auth/guest-lifecycle";
import { lobbyErrorMessage } from "@/lib/lobbies/messages";
import { HOST_SIGN_UP_HREF } from "@/lib/lobbies/hosting";
import { startableGames, type MatchGame } from "@/lib/games/catalog";

/**
 * The lobby RPCs raise short machine-readable strings — see
 * supabase/migrations/20260806200858_0005_lobby_rpc.sql. Anything absent from
 * this map is a bug rather than a player-facing condition, so it surfaces raw
 * instead of being flattened into a friendly lie.
 */
function withError(path: string, error: { message: string }): string {
  const text = lobbyErrorMessage(error.message);
  return `${path}?error=${encodeURIComponent(text)}`;
}

function normalizeCode(value: FormDataEntryValue | null): string {
  return String(value ?? "").trim().toUpperCase();
}

function validAuctionFormat(scoringMode: string, rosterPreset: string): boolean {
  return (scoringMode === "weekly" || scoringMode === "season_total")
    && ["standard", "full", "deep"].includes(rosterPreset);
}

/**
 * The era, as the form submitted it, or null for the whole pool.
 *
 * Deliberately shallow: this checks that two seasons were sent and that they
 * are numbers, and nothing else. Which years exist, which way round they go and
 * how many of them a board needs are the dealer's rules — `auction.start`
 * refuses on all three, and re-deciding them here is how the two ends drift
 * apart. An absent range is a legitimate submission, not a malformed one.
 */
function auctionSeasonRange(formData: FormData): { from: number; to: number } | null {
  const fromValue = formData.get("season_from");
  const toValue = formData.get("season_to");
  if (fromValue === null || toValue === null) return null;
  const from = Number(fromValue);
  const to = Number(toValue);
  if (!Number.isInteger(from) || !Number.isInteger(to)) return null;
  return { from, to };
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
  const { data: claimsData } = await supabase.auth.getClaims();
  if (!canCreateLobby(claimsData?.claims)) redirect(HOST_SIGN_UP_HREF);

  const { data, error } = await supabase.rpc("create_lobby");

  // redirect() unwinds by throwing, so it must never sit inside a try/catch.
  if (error) redirect(withError("/", error));

  revalidatePath("/", "layout");
  redirect(`/lobby/${data.code}`);
}

/**
 * Which game the room asked for, or null if it named one nothing can start.
 *
 * Checked against the catalogue rather than a list kept here: the catalogue is
 * where a tile says which durable record it starts, and a second list would be
 * the thing that disagrees with it.
 */
function submittedGame(value: FormDataEntryValue | null): MatchGame | null {
  const game = String(value ?? "");
  return startableGames().find((startable) => startable === game) ?? null;
}

/**
 * Turn the room into a game.
 *
 * Two calls, because the platform does not dispatch into a game's setup — it
 * does not know games exist. `start_run` freezes the roster and opens a match
 * in `setup`; the game's own RPC deals into it and moves it to `playing`. See
 * docs/architecture/architecture.md for why that seam is where it is.
 *
 * The second call is the one place in the app that has to know which game it
 * started, because each game's setup RPC lives in that game's own Postgres
 * schema and takes that game's own format. Everything above it is generic.
 */
export async function startRun(formData: FormData) {
  const lobbyId = String(formData.get("lobby_id") ?? "");
  const code = normalizeCode(formData.get("code"));
  const game = submittedGame(formData.get("game"));
  if (!game) {
    redirect(`/lobby/${code}?error=${encodeURIComponent("Pick a game that's ready to play.")}`);
  }

  const scoringMode = String(formData.get("scoring_mode") ?? "");
  const rosterPreset = String(formData.get("roster_preset") ?? "");
  if (game === "auction_team_builder" && !validAuctionFormat(scoringMode, rosterPreset)) {
    redirect(`/lobby/${code}?error=${encodeURIComponent("Choose a valid auction format.")}`);
  }
  const seasons = auctionSeasonRange(formData);
  const supabase = await createClient();

  const { data: match, error } = await supabase.rpc("start_run", {
    p_lobby_id: lobbyId,
    p_mode: "arcade",
    p_game: game,
  });
  if (error) redirect(withError(`/lobby/${code}`, error));

  // Higher or Lower sends no format yet: its scoring mode and era window are
  // arguments of the RPC with defaults it resolves and records itself, and the
  // host's picker for them is a later slice.
  const { error: dealError } = game === "auction_team_builder"
    ? await supabase.schema("auction").rpc("start", {
      p_match_id: match.id,
      p_scoring_mode: scoringMode,
      p_roster_preset: rosterPreset,
      ...(seasons ? { p_season_from: seasons.from, p_season_to: seasons.to } : {}),
    })
    : await supabase.schema("higher_or_lower").rpc("start", { p_match_id: match.id });
  if (dealError) redirect(withError(`/lobby/${code}`, dealError));

  revalidatePath("/", "layout");
  redirect(`/match/${match.id}`);
}

/** The host's final-screen choice is a room event, not personal navigation. */
export async function postGameChoice(formData: FormData) {
  const matchId = String(formData.get("match_id") ?? "");
  const code = normalizeCode(formData.get("room_code"));
  const choice = String(formData.get("choice") ?? "");
  if (!matchId || !code || (choice !== "replay" && choice !== "lobby")) {
    redirect("/");
  }

  const scoringMode = String(formData.get("scoring_mode") ?? "");
  const rosterPreset = String(formData.get("roster_preset") ?? "");
  if (choice === "replay" && (scoringMode || rosterPreset) && !validAuctionFormat(scoringMode, rosterPreset)) {
    redirect(`/match/${matchId}?error=${encodeURIComponent("Choose a valid auction format.")}`);
  }
  const seasons = auctionSeasonRange(formData);

  const supabase = await createClient();
  const { data, error } = await supabase.rpc("choose_post_game", {
    p_match_id: matchId,
    p_choice: choice,
    ...(choice === "replay" && scoringMode ? { p_scoring_mode: scoringMode } : {}),
    ...(choice === "replay" && rosterPreset ? { p_roster_preset: rosterPreset } : {}),
    ...(choice === "replay" && seasons ? { p_season_from: seasons.from, p_season_to: seasons.to } : {}),
  });
  if (error) redirect(withError(`/lobby/${code}`, error));

  revalidatePath(`/lobby/${code}`);
  redirect(data.choice === "replay" && data.next_match_id
    ? `/match/${data.next_match_id}`
    : `/lobby/${code}`);
}

/**
 * Join by code is two steps on purpose: this only navigates. The room page
 * decides whether you need to join, which means a pasted invite link and a
 * typed code land on exactly the same path.
 */
export async function goToLobby(formData: FormData) {
  const code = normalizeCode(formData.get("code"));
  if (!code) redirect(`/?error=${encodeURIComponent("Enter a room code.")}`);

  const supabase = await createClient();
  const { data: claimsData } = await supabase.auth.getClaims();
  if (!isSignedInViewer(claimsData?.claims)) redirect(`/lobby/${code}`);

  const result = await joinLobbyRpc(supabase, code);
  if (result.error) redirect(withError(`/?code=${code}`, result.error));

  revalidatePath("/", "layout");
  redirect(`/lobby/${code}`);
}

export async function joinLobby(formData: FormData) {
  const code = normalizeCode(formData.get("code"));
  const supabase = await createClient();

  const result = await joinLobbyRpc(supabase, code);

  if (result.error) redirect(withError(`/lobby/${code}`, result.error));

  revalidatePath("/", "layout");
  redirect(`/lobby/${code}`);
}

async function joinLobbyRpc(supabase: Awaited<ReturnType<typeof createClient>>, code: string) {
  let result = await supabase.rpc("join_lobby", { p_code: code });

  // Two players swapping rooms at the same instant take the lobby locks in
  // opposite order. Postgres kills one of them; retrying immediately is safe
  // because join_lobby is idempotent for a player already in the room.
  if (result.error?.code === "40P01") {
    result = await supabase.rpc("join_lobby", { p_code: code });
  }
  return result;
}

export async function leaveLobby(formData: FormData) {
  const lobbyId = String(formData.get("lobby_id") ?? "");
  const supabase = await createClient();
  const { data: claimsData } = await supabase.auth.getClaims();
  const isGuest = isGuestViewer(claimsData?.claims);

  const { error } = await supabase.rpc("leave_lobby", { p_lobby_id: lobbyId });
  if (error) redirect(withError("/", error));

  revalidatePath("/", "layout");
  redirect(isGuest ? guestSessionFinishedHref("/") : "/");
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

/** Claim controls only after the database has observed the host away for 30s. */
export async function claimLobbyHost(formData: FormData) {
  const lobbyId = String(formData.get("lobby_id") ?? "");
  const code = normalizeCode(formData.get("code"));
  const supabase = await createClient();

  const { error } = await supabase.rpc("claim_lobby_host", { p_lobby_id: lobbyId });
  if (error) redirect(withError(`/lobby/${code}`, error));

  revalidatePath(`/lobby/${code}`);
  redirect(`/lobby/${code}`);
}
