import posthog from "posthog-js";

import { hasOptOutCookie } from "@/lib/foundation/analytics/consent";

// Runs in the browser before the app becomes interactive. With no key (local
// dev, a fork, preview deployments without the variable) nothing is loaded and
// every call in lib/foundation/analytics/client.ts is a no-op.
const key = process.env.NEXT_PUBLIC_POSTHOG_KEY;

if (key) {
  try {
    posthog.init(key, {
      api_host: process.env.NEXT_PUBLIC_POSTHOG_HOST ?? "https://us.i.posthog.com",
      // Only the events in docs/analytics/events.json, plus page views. No
      // click capture, session replay, surveys or flags until we choose them.
      autocapture: false,
      capture_pageleave: false,
      capture_pageview: "history_change",
      disable_session_recording: true,
      disable_surveys: true,
      advanced_disable_flags: true,
      // Anonymous visitors don't get a person profile until they sign in.
      person_profiles: "identified_only",
      opt_out_capturing_by_default: hasOptOutCookie(document.cookie),
      // No location is inferred from the visitor's IP address.
      loaded: (client) => client.register({ platform: "web", $geoip_disable: true }),
    });
  } catch {
    // Analytics must never stop the app from starting.
  }
}
