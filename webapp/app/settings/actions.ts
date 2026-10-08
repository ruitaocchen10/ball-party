"use server";

import { revalidatePath } from "next/cache";

import { createClient } from "@/lib/supabase/server";

const AVATAR_BUCKET = "avatars";

/**
 * Removes every file in the caller's avatar folder (`{userId}/…`, the only
 * place `avatars_*_own` lets them write). This has to go through the Storage
 * API: deleting `storage.objects` rows from SQL would leave the underlying
 * file behind. Throws on failure so the account is not half-deleted — nothing
 * has been changed yet when this runs, so the player can simply retry.
 */
async function removeOwnAvatars(supabase: Awaited<ReturnType<typeof createClient>>, userId: string) {
  const bucket = supabase.storage.from(AVATAR_BUCKET);
  const { data: files, error: listError } = await bucket.list(userId);
  if (listError) throw listError;
  if (!files?.length) return;

  const { error: removeError } = await bucket.remove(files.map((file) => `${userId}/${file.name}`));
  if (removeError) throw removeError;
}

/**
 * Deletes the caller's avatar files, then runs the `delete_own_account` RPC
 * (see supabase/migrations/20261025100000_0180_delete_account_blocks_signin.sql):
 * it anonymizes `public.profiles` and bans the auth user so the old
 * password/Google login can no longer sign in. The credentials themselves stay
 * in `auth.users` — removing them needs a service-role client. Finishes by
 * signing out of every session for this account.
 *
 * Deliberately doesn't call `redirect()` itself: it's invoked from a client
 * transition (DeleteAccountSection), not a `<form action>`, so the caller
 * navigates once this resolves rather than racing a thrown redirect.
 */
export async function deleteAccount() {
  const supabase = await createClient();
  const { data } = await supabase.auth.getClaims();
  const userId = data?.claims?.sub;
  if (!userId) throw new Error("not_authenticated");

  await removeOwnAvatars(supabase, userId);

  const { error } = await supabase.rpc("delete_own_account");
  if (error) throw error;

  await supabase.auth.signOut({ scope: "global" });
  revalidatePath("/", "layout");
}
