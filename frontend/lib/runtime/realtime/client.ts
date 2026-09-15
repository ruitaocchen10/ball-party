import { createClient } from "@/lib/supabase/client";

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
