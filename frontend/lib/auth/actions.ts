"use server";

import { headers } from "next/headers";
import { redirect } from "next/navigation";
import { revalidatePath } from "next/cache";

import { safeNextPath } from "@/lib/auth/next";
import { createClient } from "@/lib/supabase/server";
import {
  DISPLAY_NAME_MAX,
  DISPLAY_NAME_MIN,
  PASSWORD_MIN,
  type AuthState,
} from "@/lib/auth/types";

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
  const { error } = await supabase.auth.signInWithPassword({ email, password });

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

  revalidatePath("/", "layout");
  redirect(next);
}

export async function signUpWithEmail(
  _prev: AuthState,
  formData: FormData,
): Promise<AuthState> {
  const displayName = String(formData.get("display_name") ?? "").trim();
  const email = String(formData.get("email") ?? "").trim().toLowerCase();
  const password = String(formData.get("password") ?? "");
  const next = safeNextPath(formData.get("next"));

  if (displayName.length < DISPLAY_NAME_MIN || displayName.length > DISPLAY_NAME_MAX) {
    return {
      error: `Display name must be ${DISPLAY_NAME_MIN}–${DISPLAY_NAME_MAX} characters.`,
    };
  }
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
      data: { display_name: displayName },
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
  redirect("/login");
}
