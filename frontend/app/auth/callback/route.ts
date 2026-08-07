import { NextResponse, type NextRequest } from "next/server";

import { safeNextPath } from "@/lib/auth/next";
import { createClient } from "@/lib/supabase/server";

/**
 * OAuth (PKCE) landing point. Google redirects here with `?code=`, which we
 * trade for a session using the verifier cookie written when the flow started.
 */
export async function GET(request: NextRequest) {
  const { searchParams, origin } = new URL(request.url);

  const code = searchParams.get("code");
  const next = safeNextPath(searchParams.get("next"), origin);

  // The user hit "Cancel" on Google's consent screen, or the provider failed.
  const providerError = searchParams.get("error_description") ?? searchParams.get("error");
  if (providerError) {
    return NextResponse.redirect(
      `${origin}/auth/auth-code-error?reason=${encodeURIComponent(providerError)}`,
    );
  }

  if (!code) {
    return fail(origin, "Google redirected back without an authorization code.");
  }

  const supabase = await createClient();
  const { error } = await supabase.auth.exchangeCodeForSession(code);

  if (error) {
    // Surfaced rather than swallowed: the two realistic causes here — a missing
    // PKCE verifier cookie and a code already redeemed by a duplicate request —
    // are indistinguishable from a blank error page.
    console.error("[auth/callback] code exchange failed", {
      code: error.code,
      status: error.status,
      message: error.message,
    });
    return fail(origin, error.message);
  }

  // Behind Vercel's load balancer `origin` is the internal host, so prefer
  // the forwarded one in production or the redirect leaves the site.
  const forwardedHost = request.headers.get("x-forwarded-host");
  const base =
    process.env.NODE_ENV === "development" || !forwardedHost
      ? origin
      : `https://${forwardedHost}`;
  return NextResponse.redirect(`${base}${next}`);
}

function fail(origin: string, reason: string) {
  return NextResponse.redirect(
    `${origin}/auth/auth-code-error?reason=${encodeURIComponent(reason)}`,
  );
}
