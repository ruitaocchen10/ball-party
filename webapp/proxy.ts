import type { NextRequest } from "next/server";
import { updateSession } from "@/lib/supabase/proxy";

// Next.js 16 renamed Middleware to Proxy. Same execution model: runs before the
// route renders, on every matched request.
export async function proxy(request: NextRequest) {
  return updateSession(request);
}

export const config = {
  matcher: [
    /*
     * Everything except static assets and the files crawlers and link-preview
     * bots fetch. Without the asset exclusions the auth redirect would also
     * fire for CSS, JS and images, and the app would render unstyled. Without
     * the crawler ones a signed-out bot asking for /robots.txt or
     * /sitemap.xml is redirected to /login and never sees them — the same goes
     * for the site-wide /opengraph-image card and the web app manifest.
     * `.well-known/` is the same: iOS fetches
     * /.well-known/apple-app-site-association with no session to verify
     * Universal Links, and a redirect to /login fails it.
     * (Per-prompt images live under /prompts, which is already public.)
     */
    "/((?!_next/static|_next/image|favicon.ico|robots\\.txt|\\.well-known/|sitemap\\.xml|manifest\\.webmanifest|opengraph-image|twitter-image|.*\\.(?:svg|png|jpg|jpeg|gif|webp|ico)$).*)",
  ],
};
