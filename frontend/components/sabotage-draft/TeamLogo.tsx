"use client";

import { useState } from "react";

import { franchiseLogoUrl } from "@/lib/sabotage-draft/franchises";

/**
 * A franchise's logo, decorative next to the team name text every caller
 * already renders alongside it -- `alt=""` on purpose, the name carries the
 * accessible label. Not every franchise code is guaranteed to have a file in
 * the `team-logos` bucket (see `franchiseLogoUrl`'s own doc comment), so a
 * 404 hides the element entirely via `onError` rather than showing a broken-
 * image icon: a missing logo degrades to "just the text," which is exactly
 * what every one of these call sites rendered before logos existed at all.
 */
export function TeamLogo({ code, className = "h-5 w-5" }: { code: string; className?: string }) {
  const [failed, setFailed] = useState(false);
  if (failed) return null;
  return (
    <img
      src={franchiseLogoUrl(code)}
      alt=""
      aria-hidden="true"
      className={`shrink-0 object-contain ${className}`}
      onError={() => setFailed(true)}
    />
  );
}
