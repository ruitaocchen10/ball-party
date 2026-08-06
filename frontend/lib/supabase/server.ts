import { createServerClient } from "@supabase/ssr";
import { cookies } from "next/headers";

/**
 * Supabase client for Server Components, Server Actions and Route Handlers.
 *
 * Create a new one per request — never hoist it into a module-level singleton,
 * or one request's session can leak into another under fluid compute.
 */
export async function createClient() {
  const cookieStore = await cookies();

  return createServerClient(
    process.env.NEXT_PUBLIC_SUPABASE_URL!,
    process.env.NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY!,
    {
      cookies: {
        /*
         * Keep the user object out of the cookie; store only the access and
         * refresh tokens. A Google identity carries enough metadata (avatar
         * URL, provider tokens, full profile) that the default
         * `user-and-tokens` encoding overflowed Node's 16KB request header
         * limit and the dev server answered HTTP 431.
         *
         * The trade: `getSession().data.session.user` is no longer populated.
         * We read identity through `getClaims()` everywhere, which is the
         * recommended pairing anyway. Must match client.ts and proxy.ts.
         */
        encode: "tokens-only",
        getAll() {
          return cookieStore.getAll();
        },
        setAll(cookiesToSet) {
          try {
            for (const { name, value, options } of cookiesToSet) {
              cookieStore.set(name, value, options);
            }
          } catch {
            // Server Components cannot write cookies. Safe to swallow: proxy.ts
            // refreshes the session on every request, so the tokens still rotate.
          }
        },
      },
    },
  );
}
