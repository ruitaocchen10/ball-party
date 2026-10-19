"use client";

import { useEffect } from "react";

import { identify, resetIdentity } from "@/lib/foundation/analytics/client";
import { createClient } from "@/lib/supabase/client";

/**
 * Keeps PostHog's idea of who is here in step with the Supabase session. It
 * listens in the browser rather than reading claims in the root layout, which
 * would make every page dynamic.
 */
export function AnalyticsIdentity() {
  useEffect(() => {
    if (!process.env.NEXT_PUBLIC_POSTHOG_KEY) return;

    const { data } = createClient().auth.onAuthStateChange((event, session) => {
      if (session?.user) {
        identify(session.user.id, { is_guest: session.user.is_anonymous === true });
      } else if (event === "SIGNED_OUT") {
        resetIdentity();
      }
    });
    return () => data.subscription.unsubscribe();
  }, []);

  return null;
}
