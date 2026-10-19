import { cookies } from "next/headers";
import { after } from "next/server";
import { PostHog } from "posthog-node";

import { hasOptOutCookie } from "@/lib/foundation/analytics/consent";
import type { AnalyticsEventName, AnalyticsEvents } from "@/lib/foundation/analytics/events";
import type { createClient } from "@/lib/supabase/server";

const DEFAULT_HOST = "https://us.i.posthog.com";

/**
 * Sends an event from a server action or route handler, for moments that end in
 * a redirect and so have no client code to report them. Honors the same opt-out
 * cookie the browser does, and does nothing when no key is configured.
 *
 * The send is scheduled with `after()`, so it never delays the response and
 * still runs when the action finishes in `redirect()` (which throws).
 */
export async function trackServer<E extends AnalyticsEventName>(
  userId: string | null | undefined,
  event: E,
  props: AnalyticsEvents[E],
): Promise<void> {
  const key = process.env.NEXT_PUBLIC_POSTHOG_KEY;
  if (!key || !userId) return;

  try {
    if (hasOptOutCookie((await cookies()).toString())) return;

    const host = process.env.NEXT_PUBLIC_POSTHOG_HOST ?? DEFAULT_HOST;
    after(async () => {
      const client = new PostHog(key, { host, flushAt: 1, flushInterval: 0 });
      try {
        await client.captureImmediate({
          distinctId: userId,
          event,
          // The request comes from our server, so GeoIP would place everyone in
          // the Vercel region.
          properties: { ...props, platform: "web", $geoip_disable: true },
        });
      } catch {
        // Nothing to do: the event is dropped, the response is long gone.
      } finally {
        await client._shutdown();
      }
    });
  } catch {
    // Analytics failures (and a call outside a request, as in unit tests) are
    // never the player's problem.
  }
}

/** `trackServer` for the signed-in viewer behind a Supabase server client. */
export async function trackServerAs<E extends AnalyticsEventName>(
  supabase: Awaited<ReturnType<typeof createClient>>,
  event: E,
  props: AnalyticsEvents[E],
): Promise<void> {
  const { data } = await supabase.auth.getClaims();
  await trackServer(data?.claims?.sub, event, props);
}
