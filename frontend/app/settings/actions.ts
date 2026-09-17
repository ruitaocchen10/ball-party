"use server";

import { revalidatePath } from "next/cache";

import { canViewProfile } from "@/lib/foundation/identity/viewer";
import { createClient } from "@/lib/supabase/server";

export type SettingsUpdateState = { error: string | null };

/**
 * Called directly from the client (not as a `<form action>`) — a single
 * boolean doesn't need FormData, and a real form submission here would hit
 * React's post-action reset, which snaps a controlled checkbox back to its
 * original value regardless of the state that set it.
 */
export async function updateRankingsVisibility(visible: boolean): Promise<SettingsUpdateState> {
  const supabase = await createClient();
  const { data } = await supabase.auth.getClaims();
  const userId = data?.claims?.sub;
  if (!userId || !canViewProfile(data?.claims)) return { error: "Create an account to change this." };

  const { error } = await supabase.from("profiles").update({ rankings_visible: visible }).eq("id", userId);
  if (error) return { error: "We couldn’t save that. Please try again." };

  revalidatePath("/settings");
  revalidatePath("/profile");
  return { error: null };
}

/**
 * Anonymizes via the `delete_own_account` RPC (see
 * supabase/migrations/20260916163000_0110_delete_own_account.sql for why this
 * only scrubs `public.profiles` rather than revoking auth credentials), then
 * signs out of every session for this account — the one mitigation available,
 * without a service-role client, for the fact that the old password/Google
 * login still technically works afterward.
 *
 * Deliberately doesn't call `redirect()` itself: it's invoked from a client
 * transition (DeleteAccountSection), not a `<form action>`, so the caller
 * navigates once this resolves rather than racing a thrown redirect.
 */
export async function deleteAccount() {
  const supabase = await createClient();
  const { error } = await supabase.rpc("delete_own_account");
  if (error) throw error;

  await supabase.auth.signOut({ scope: "global" });
  revalidatePath("/", "layout");
}
