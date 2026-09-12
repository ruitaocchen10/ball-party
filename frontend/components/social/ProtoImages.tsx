"use client";

import { useState } from "react";

import { teamLogoCode } from "@/lib/nfl/team-logos";

/**
 * PROTOTYPE — throwaway. `@/components/ui/TeamLogo` builds its URL from
 * `NEXT_PUBLIC_SUPABASE_URL`, which in local dev points at the Supabase
 * container — not running on every machine that opens this prototype. Real
 * code should keep using `TeamLogo`; this points at the same public bucket on
 * the hosted project directly, so the demo renders real logos regardless of
 * whether the local stack is up. `teamLogoCode` itself is the app's own pure
 * mapping, not env-dependent, so it's the one piece worth importing rather
 * than copying.
 */
const LOGO_BUCKET = "https://xjsbmxgnmrvqfsqcohjv.supabase.co/storage/v1/object/public/team-logos";

export function ProtoTeamLogo({ code, className = "h-5 w-5" }: { code: string; className?: string }) {
  const [failed, setFailed] = useState(false);
  const logoCode = teamLogoCode(code);
  if (!logoCode || failed) return null;
  return (
    <img
      src={`${LOGO_BUCKET}/${logoCode}.png`}
      alt=""
      aria-hidden="true"
      className={`shrink-0 object-contain ${className}`}
      onError={() => setFailed(true)}
    />
  );
}

/**
 * Real NFL.com headshot URLs pulled from this project's own auction lots —
 * see mockData.ts. Same onError-falls-back-to-initials posture as the real
 * app's PlayerPortrait/LotPortrait (SabotageDraftMatch.tsx, AuctionMatch.tsx)
 * — duplicated here rather than imported since those are private to their
 * own match components.
 */
export function PlayerPortrait({
  name,
  headshotUrl,
  className = "h-8 w-8",
}: {
  name: string;
  headshotUrl?: string | null;
  className?: string;
}) {
  const [failed, setFailed] = useState(false);
  const showImage = Boolean(headshotUrl) && !failed;
  return (
    <span className={`inline-flex shrink-0 items-center justify-center overflow-hidden rounded-full bg-surface ${className}`}>
      {showImage ? (
        <img src={headshotUrl!} alt="" className="h-full w-full object-cover object-top" onError={() => setFailed(true)} />
      ) : (
        <span className="flex h-full w-full items-center justify-center bg-hidden font-slab text-panel">
          <span className="font-slab-optical-center">{initials(name)}</span>
        </span>
      )}
    </span>
  );
}

function initials(name: string): string {
  return name.trim().split(/\s+/).filter(Boolean).slice(0, 2).map((part) => part[0]?.toUpperCase()).join("") || "?";
}
