import type { EmailOtpType } from "@supabase/supabase-js";
import { NextResponse, type NextRequest } from "next/server";

import { safeNextPath } from "@/lib/auth/next";
import { createClient } from "@/lib/supabase/server";

/**
 * Email link landing point — signup confirmations, password recovery, email
 * changes. Requires the Supabase email templates to point here with a token
 * hash rather than at the default `{{ .ConfirmationURL }}`; see docs/auth.md.
 */
export async function GET(request: NextRequest) {
  const { searchParams, origin } = new URL(request.url);

  const tokenHash = searchParams.get("token_hash");
  const type = searchParams.get("type") as EmailOtpType | null;
  // Supabase renders `{{ .RedirectTo }}` as the absolute URL we passed to
  // `emailRedirectTo`, so `next` arrives here fully qualified, not as a path.
  const next = safeNextPath(searchParams.get("next"), origin);

  if (tokenHash && type) {
    const supabase = await createClient();
    const { error } = await supabase.auth.verifyOtp({ type, token_hash: tokenHash });
    if (!error) {
      return NextResponse.redirect(`${origin}${next}`);
    }
  }

  return NextResponse.redirect(
    `${origin}/auth/auth-code-error?reason=${encodeURIComponent(
      "That confirmation link is invalid or has already been used.",
    )}`,
  );
}
