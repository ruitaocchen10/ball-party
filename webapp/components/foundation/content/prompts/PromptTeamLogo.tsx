"use client";

import { useState } from "react";

import { franchiseLogoUrl, teamLogoCode } from "@/lib/foundation/content/nfl/team-logos";

/**
 * Franchise mark for a prompt slot, given a raw team abbreviation (e.g.
 * "BUF") rather than an already-resolved logo code — unlike
 * `@/components/foundation/ui-kit/TeamLogo`, whose callers pass the resolved
 * code directly.
 */
export function PromptTeamLogo({ code, className = "h-5 w-5" }: { code: string; className?: string }) {
  const [failed, setFailed] = useState(false);
  const logoCode = teamLogoCode(code);
  if (!logoCode || failed) return null;
  return (
    <img
      src={franchiseLogoUrl(logoCode)}
      alt=""
      aria-hidden="true"
      className={`shrink-0 object-contain ${className}`}
      onError={() => setFailed(true)}
    />
  );
}
