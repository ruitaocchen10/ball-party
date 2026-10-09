"use server";

import { revalidatePath } from "next/cache";

import { canViewProfile } from "@/lib/foundation/identity/viewer";
import { createClient } from "@/lib/supabase/server";
import { validateProfileUpdate } from "@/lib/foundation/identity/validation";
import { usernameClaimError, usernameFormatHint } from "@/lib/foundation/identity/username";

export type ProfileUpdateState = { error: string | null; saved: boolean };

export type UsernameAvailability = { available: boolean | null; error: string | null };
export type ClaimUsernameState = { error: string | null; username: string | null };

/**
 * Asks the `username_available` RPC (the only authority on the rules) whether
 * the caller could claim this name. `available` is null when we couldn't find
 * out; the RPC itself is rate limited, so a rejection reads as "slow down".
 */
export async function checkUsernameAvailable(username: string): Promise<UsernameAvailability> {
  const supabase = await createClient();
  const { data } = await supabase.auth.getClaims();
  if (!canViewProfile(data?.claims)) return { available: null, error: "Create an account to pick a username." };

  const { data: available, error } = await supabase.rpc("username_available", { p_username: username });
  if (error) {
    return {
      available: null,
      error: error.message.includes("rate_limited")
        ? "Slow down a little, then try again."
        : "We couldn’t check that username right now.",
    };
  }
  return { available, error: null };
}

/** Claims a username on its own (the one-time confirm prompt). */
export async function claimUsername(username: string): Promise<ClaimUsernameState> {
  const supabase = await createClient();
  const { data } = await supabase.auth.getClaims();
  if (!canViewProfile(data?.claims)) return { error: "Create an account to pick a username.", username: null };

  const { data: stored, error } = await supabase.rpc("claim_username", { p_username: username });
  if (error) return { error: usernameClaimError(error), username: null };

  revalidatePath("/profile");
  revalidatePath("/", "layout");
  return { error: null, username: stored };
}

export async function updateProfile(
  _previous: ProfileUpdateState,
  formData: FormData,
): Promise<ProfileUpdateState> {
  const update = validateProfileUpdate(
    String(formData.get("display_name") ?? ""),
    String(formData.get("avatar_url") ?? ""),
  );
  if ("error" in update) return { error: update.error, saved: false };

  const username = String(formData.get("username") ?? "").trim();
  const currentUsername = String(formData.get("current_username") ?? "");
  const usernameChanged = username !== "" && username !== currentUsername;
  if (usernameChanged) {
    const hint = usernameFormatHint(username);
    if (hint) return { error: hint, saved: false };
  }

  const supabase = await createClient();
  const { data } = await supabase.auth.getClaims();
  const userId = data?.claims?.sub;
  if (!userId || !canViewProfile(data?.claims)) return { error: "Create an account to save a profile.", saved: false };

  // The username goes first: it's the part that can legitimately be refused
  // (taken, reserved), and then a refusal leaves nothing half-saved.
  if (usernameChanged) {
    const { error: usernameError } = await supabase.rpc("claim_username", { p_username: username });
    if (usernameError) return { error: usernameClaimError(usernameError), saved: false };
  }

  const { error } = await supabase
    .from("profiles")
    .update({ display_name: update.displayName, avatar_url: update.avatarUrl })
    .eq("id", userId);
  if (error) return { error: "We couldn’t save your profile. Please try again.", saved: false };

  revalidatePath("/profile");
  revalidatePath("/", "layout");
  return { error: null, saved: true };
}
