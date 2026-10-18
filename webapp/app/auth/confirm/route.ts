import type { EmailOtpType } from "@supabase/supabase-js";
import { NextResponse, type NextRequest } from "next/server";

import { safeNextPath } from "@/lib/foundation/identity/next";
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
    const { data, error } = await supabase.auth.verifyOtp({ type, token_hash: tokenHash });
    if (!error) {
      // The username typed at signup waits in user metadata (the database
      // assigns a generated one meanwhile). Claim it now that there is a
      // session; a taken or reserved name just keeps the generated one.
      const preferred = data.user?.user_metadata?.username;
      if (type === "signup" && typeof preferred === "string") {
        await supabase.rpc("claim_username", { p_username: preferred });
      }
      return NextResponse.redirect(`${origin}${next}`);
    }
  }

  return NextResponse.redirect(
    `${origin}/auth/auth-code-error?reason=${encodeURIComponent(
      "That confirmation link is invalid or has already been used.",
    )}`,
  );
}
