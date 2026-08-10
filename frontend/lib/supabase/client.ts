import { createBrowserClient } from "@supabase/ssr";

import type { Database } from "@/lib/supabase/database.types";

/**
 * Supabase client for Client Components. Reads the session from cookies written
 * by the server client, so browser and server stay on the same session.
 *
 * Typed against database.types.ts, which is generated from the live schema.
 * Regenerate it whenever a migration changes a table or an RPC signature.
 */
export function createClient() {
  return createBrowserClient<Database>(
    process.env.NEXT_PUBLIC_SUPABASE_URL!,
    process.env.NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY!,
    {
      cookies: {
        // Must match the server and proxy clients. See lib/supabase/server.ts.
        // No getAll/setAll here on purpose: in a browser `@supabase/ssr` falls
        // through to the document.cookie API, and this object exists only to
        // carry `encode`. That fall-through is browser-only, so this must never
        // be called while rendering on the server — see createRealtimeClient.
        encode: "tokens-only",
      },
    },
  );
}

/**
 * A client whose Realtime socket is authenticated as the signed-in user.
 *
 * Subscribing without this silently produces a socket that authenticates with
 * the publishable key alone, so Realtime records the subscription as `anon`.
 * Every table we stream gates SELECT on `auth.uid()` — `is_lobby_member`,
 * `is_run_member`, `is_match_member` — so an anonymous subscriber matches no
 * rows and receives nothing at all. Nothing errors; the events just never
 * arrive, which is the worst shape a bug like this can take.
 *
 * The token has to be applied *before* `subscribe()`, because the subscription
 * is registered with the claims the socket holds at join time. supabase-js
 * applies it on its own eventually, but a subscribe() in an effect wins that
 * race, which is why this is explicit rather than left to timing.
 */
export async function createRealtimeClient() {
  const supabase = createClient();
  const {
    data: { session },
  } = await supabase.auth.getSession();
  await supabase.realtime.setAuth(session?.access_token ?? null);
  return supabase;
}
