import { createBrowserClient } from "@supabase/ssr";

/**
 * Supabase client for Client Components. Reads the session from cookies written
 * by the server client, so browser and server stay on the same session.
 */
export function createClient() {
  return createBrowserClient(
    process.env.NEXT_PUBLIC_SUPABASE_URL!,
    process.env.NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY!,
    {
      cookies: {
        // Must match the server and proxy clients. See lib/supabase/server.ts.
        encode: "tokens-only",
      },
    },
  );
}
