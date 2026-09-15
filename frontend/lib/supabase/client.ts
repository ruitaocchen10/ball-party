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
        // be called while rendering on the server — see createRealtimeClient
        // in lib/runtime/realtime/client.ts.
        encode: "tokens-only",
      },
    },
  );
}
