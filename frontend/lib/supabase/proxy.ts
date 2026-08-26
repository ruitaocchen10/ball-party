import { createServerClient } from "@supabase/ssr";
import { NextResponse, type NextRequest } from "next/server";
import { isGuestViewer, isSignedInViewer } from "@/lib/auth/viewer";

/**
 * Paths reachable while signed out. Everything else redirects to /login.
 *
 * `/` and `/lobby` are public because they are the two ways anyone arrives:
 * the home screen for a stranger, an invite link for a friend. Both render
 * their own signed-out state with the actions gated, which is why there is no
 * separate marketing page to keep in sync. RLS still returns nothing about a
 * room to someone who is not a member of it.
 */
const PUBLIC_PATHS = ["/", "/login", "/signup", "/check-email", "/auth", "/lobby", "/party", "/solo", "/social"];

/** Signed-in users bounced off these back to the app. */
const AUTH_ONLY_PATHS = ["/login", "/signup"];

function matches(pathname: string, paths: string[]) {
  return paths.some((p) => pathname === p || pathname.startsWith(`${p}/`));
}

export async function updateSession(request: NextRequest) {
  let response = NextResponse.next({ request });

  const supabase = createServerClient(
    process.env.NEXT_PUBLIC_SUPABASE_URL!,
    process.env.NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY!,
    {
      cookies: {
        // Must match the browser and server clients. See lib/supabase/server.ts.
        encode: "tokens-only",
        getAll() {
          return request.cookies.getAll();
        },
        setAll(cookiesToSet, headers) {
          for (const { name, value } of cookiesToSet) {
            request.cookies.set(name, value);
          }
          response = NextResponse.next({ request });
          for (const { name, value, options } of cookiesToSet) {
            response.cookies.set(name, value, options);
          }
          // Cache-Control etc. Responses that set auth cookies must never be
          // cached by a CDN, or one user's tokens get served to another.
          for (const [key, value] of Object.entries(headers)) {
            response.headers.set(key, value);
          }
        },
      },
    },
  );

  // Do not put code between createServerClient and getClaims(). Anything that
  // touches cookies in between desynchronises the browser and the server and
  // shows up as users being randomly logged out.
  const { data } = await supabase.auth.getClaims();
  const claims = data?.claims;

  const signedIn = isSignedInViewer(claims);

  const { pathname } = request.nextUrl;

  if (!signedIn && !matches(pathname, PUBLIC_PATHS)) {
    const url = request.nextUrl.clone();
    url.pathname = "/login";
    url.search = "";
    if (pathname !== "/") url.searchParams.set("next", pathname);
    return NextResponse.redirect(url);
  }

  // A guest may still visit sign-in to choose an existing account.  That
  // intentionally records the separate guest identity rather than merging it.
  if (signedIn && !isGuestViewer(claims) && matches(pathname, AUTH_ONLY_PATHS)) {
    const url = request.nextUrl.clone();
    url.pathname = "/";
    url.search = "";
    return NextResponse.redirect(url);
  }

  // Must be returned as-is. Building a fresh NextResponse here would drop the
  // refreshed auth cookies set above.
  return response;
}
