import { createClient as createSupabaseClient } from "@supabase/supabase-js";

import type { Database } from "@/lib/supabase/database.types";

/**
 * Cookie-less Supabase client for public reads that no viewer's session should
 * influence — the sitemap, link-preview metadata and OG images. It always acts
 * as `anon`, so it sees exactly what a signed-out visitor sees (see migration
 * 0112_public_prompt_reads) and nothing an account holder could.
 *
 * Deliberately not built on lib/supabase/server.ts: that one reads `cookies()`,
 * which opts the caller into per-request rendering and would make the sitemap
 * and OG images uncacheable.
 */
export function createPublicClient() {
  return createSupabaseClient<Database>(
    process.env.NEXT_PUBLIC_SUPABASE_URL!,
    process.env.NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY!,
    { auth: { persistSession: false, autoRefreshToken: false } },
  );
}
