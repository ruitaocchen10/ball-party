"use client";

import { useState } from "react";

import { franchiseLogoUrl } from "@/lib/nfl/team-logos";

/**
 * Decorative franchise mark for any game that already renders the team name.
 * A missing bucket object hides on error, preserving the text-only fallback.
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
