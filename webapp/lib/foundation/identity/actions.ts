"use server";

import { headers } from "next/headers";
import { redirect } from "next/navigation";
import { revalidatePath } from "next/cache";

import { trackServer } from "@/lib/foundation/analytics/server";
import { safeNextPath } from "@/lib/foundation/identity/next";
import { createClient } from "@/lib/supabase/server";
import { usernameFormatHint } from "@/lib/foundation/identity/username";
import {
  DISPLAY_NAME_MAX,
  DISPLAY_NAME_MIN,
  PASSWORD_MIN,
  type AuthState,
} from "@/lib/foundation/identity/types";

/**
 * Absolute base URL for email and OAuth redirects. Prefer the configured value
 * — on Vercel the request host varies per deployment, and a preview URL baked
 * into a confirmation email breaks the link for good.
 */
async function siteUrl(): Promise<string> {
  const configured = process.env.NEXT_PUBLIC_SITE_URL;
  if (configured) return configured.replace(/\/$/, "");

  const h = await headers();
  const host = h.get("x-forwarded-host") ?? h.get("host") ?? "localhost:3000";
  const proto = h.get("x-forwarded-proto") ?? (host.startsWith("localhost") ? "http" : "https");
  return `${proto}://${host}`;
}

export async function signInWithEmail(
  _prev: AuthState,
  formData: FormData,
): Promise<AuthState> {
  const email = String(formData.get("email") ?? "").trim().toLowerCase();
  const password = String(formData.get("password") ?? "");
  const next = safeNextPath(formData.get("next"));

  if (!email || !password) {
    return { error: "Enter your email and password." };
  }

  const supabase = await createClient();

  // Stake the guest's claim while the guest session is still the one we hold.
  // That is the only moment auth.uid() can prove who is making it, which is why
  // it happens here rather than after the sign-in below. The nonce is the proof
  // carried across, and it never leaves this action.
  const { data: beforeSignIn } = await supabase.auth.getClaims();
  let guestClaim: string | null = null;
  if (beforeSignIn?.claims?.is_anonymous === true) {
    const { data } = await supabase.rpc("claim_guest_identity");
    guestClaim = data ?? null;
  }

  const { data: signedIn, error } = await supabase.auth.signInWithPassword({ email, password });

  if (error) {
    // Deliberately vague on bad credentials so the form can't be used to test
    // whether an address has an account here.
    return {
      error:
        error.code === "email_not_confirmed"
          ? "Confirm your email address first — check your inbox for the link."
          : "That email and password don't match an account.",
    };
  }

  // Signing into a separate account cannot merge a guest's match history
  // safely. Preserve the relationship instead, so it can be reattached if a
  // cross-run feature eventually needs it. Redeeming is best-effort: a stale or
  // expired claim must not cost someone the sign-in they actually asked for.
  if (guestClaim) {
    await supabase.rpc("record_guest_account_collision", { p_nonce: guestClaim });
  }

  await trackServer(signedIn.user?.id, "signed_in", { method: "email" });

  revalidatePath("/", "layout");
  redirect(next);
}

export async function signUpWithEmail(
  _prev: AuthState,
  formData: FormData,
): Promise<AuthState> {
  const displayName = String(formData.get("display_name") ?? "").trim();
  const username = String(formData.get("username") ?? "").trim();
  const email = String(formData.get("email") ?? "").trim().toLowerCase();
  const password = String(formData.get("password") ?? "");
  const next = safeNextPath(formData.get("next"));

  if (displayName.length < DISPLAY_NAME_MIN || displayName.length > DISPLAY_NAME_MAX) {
    return {
      error: `Display name must be ${DISPLAY_NAME_MIN}–${DISPLAY_NAME_MAX} characters.`,
    };
  }
  // Only the shape is checked here. Whether the name is free or reserved is
  // decided by claim_username once the player has a session.
  const usernameHint = username ? usernameFormatHint(username) : null;
  if (usernameHint) return { error: usernameHint };
  if (!/^[^@\s]+@[^@\s]+\.[^@\s]+$/.test(email)) {
    return { error: "Enter a valid email address." };
  }
  if (password.length < PASSWORD_MIN) {
    return { error: `Password must be at least ${PASSWORD_MIN} characters.` };
  }

  const supabase = await createClient();
  const { error } = await supabase.auth.signUp({
    email,
    password,
    options: {
      // Read by the handle_new_user trigger to seed public.profiles.
      // `username` is only the player's preference: no session exists to claim
      // it with until the email is confirmed, so the home page claims it then.
      data: { display_name: displayName, ...(username ? { username } : {}) },
      // The destination, not the confirm route. Supabase renders this as
      // `{{ .RedirectTo }}` in the email template, and /auth/confirm reduces it
      // back to a path after verifying the token. Sending the confirm route
      // here instead is how an invited player used to lose the room they were
      // invited to and land on the home page.
      emailRedirectTo: `${await siteUrl()}${next}`,
    },
  });

  if (error) {
    return { error: error.message };
  }

  // With email enumeration protection on, signing up with an address that
  // already exists succeeds here and sends that address a "someone tried to
  // register you" email instead. Same destination either way, by design.
  redirect("/check-email");
}

export async function signInWithGoogle(formData: FormData) {
  const next = safeNextPath(formData.get("next"));
  const supabase = await createClient();

  const { data, error } = await supabase.auth.signInWithOAuth({
    provider: "google",
    options: {
      redirectTo: `${await siteUrl()}/auth/callback?next=${encodeURIComponent(next)}`,
    },
  });

  if (error || !data.url) {
    redirect("/auth/auth-code-error");
  }

  // Hands off to Google. The PKCE verifier was just written to a cookie by the
  // server client above, and /auth/callback trades it back for a session.
  redirect(data.url);
}

export async function signOut() {
  const supabase = await createClient();
  await supabase.auth.signOut();
  revalidatePath("/", "layout");
  redirect("/");
}
