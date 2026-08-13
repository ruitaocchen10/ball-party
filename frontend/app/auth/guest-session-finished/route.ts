import { NextResponse, type NextRequest } from "next/server";

import { safeNextPath } from "@/lib/auth/next";
import { isGuestViewer } from "@/lib/auth/viewer";
import { createClient } from "@/lib/supabase/server";

/**
 * Ends a completed party's anonymous session before returning to the lobby.
 * Credentialed accounts pass through unchanged, so this is safe as a shared
 * post-game destination.
 */
export async function GET(request: NextRequest) {
  const { origin, searchParams } = new URL(request.url);
  const next = safeNextPath(searchParams.get("next"), origin);
  const supabase = await createClient();
  const { data } = await supabase.auth.getClaims();

  if (isGuestViewer(data?.claims)) await supabase.auth.signOut();

  return NextResponse.redirect(`${origin}${next}`);
}
