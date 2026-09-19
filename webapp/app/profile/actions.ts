"use server";

import { revalidatePath } from "next/cache";

import { canViewProfile } from "@/lib/foundation/identity/viewer";
import { createClient } from "@/lib/supabase/server";
import { validateProfileUpdate } from "@/lib/foundation/identity/validation";

export type ProfileUpdateState = { error: string | null; saved: boolean };

export async function updateProfile(
  _previous: ProfileUpdateState,
  formData: FormData,
): Promise<ProfileUpdateState> {
  const update = validateProfileUpdate(
    String(formData.get("display_name") ?? ""),
    String(formData.get("avatar_url") ?? ""),
  );
  if ("error" in update) return { error: update.error, saved: false };

  const supabase = await createClient();
  const { data } = await supabase.auth.getClaims();
  const userId = data?.claims?.sub;
  if (!userId || !canViewProfile(data?.claims)) return { error: "Create an account to save a profile.", saved: false };

  const { error } = await supabase
    .from("profiles")
    .update({ display_name: update.displayName, avatar_url: update.avatarUrl })
    .eq("id", userId);
  if (error) return { error: "We couldn’t save your profile. Please try again.", saved: false };

  revalidatePath("/profile");
  revalidatePath("/", "layout");
  return { error: null, saved: true };
}
