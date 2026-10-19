"use client";

import { useSyncExternalStore } from "react";

import { isOptedOut, setOptedOut } from "@/lib/foundation/analytics/client";

// The choice lives in a cookie, which can't announce changes, so the toggle
// notifies its own subscribers when it writes one.
const listeners = new Set<() => void>();
function subscribe(listener: () => void) {
  listeners.add(listener);
  return () => void listeners.delete(listener);
}

/** Saves on toggle, like PrivateProfileToggle. The choice lives in this browser only. */
export function AnalyticsToggle() {
  // The server render has no cookie to read and assumes the default (on); the
  // first client render then corrects it for anyone who opted out.
  const shareUsage = useSyncExternalStore(subscribe, () => !isOptedOut(), () => true);

  function toggle(next: boolean) {
    setOptedOut(!next);
    listeners.forEach((listener) => listener());
  }

  return (
    <label className="flex items-start gap-3">
      <input
        type="checkbox"
        checked={shareUsage}
        onChange={(event) => toggle(event.target.checked)}
        className="mt-1 h-4 w-4 shrink-0 accent-panel-fg"
      />
      <span>
        <span className="block text-sm font-semibold text-fg">Share usage data</span>
        <span className="mt-1 block max-w-[48ch] text-sm leading-5 text-fg-muted">
          Helps us see which features get used so we can improve Ball Party. It never includes your email or what you type. This applies to this browser only.
        </span>
      </span>
    </label>
  );
}
