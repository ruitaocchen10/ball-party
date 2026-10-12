"use client";

import { useState } from "react";

/**
 * Real NFL.com headshot URLs pulled from this project's own auction lots —
 * see staticOptionPools.ts. Same onError-falls-back-to-initials posture as
 * the real app's LotPortrait (AuctionMatch.tsx) — duplicated here rather than
 * imported since it is private to its own match component.
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
    <span className={`inline-flex shrink-0 items-center justify-center overflow-hidden rounded-card bg-surface ${className}`}>
      {showImage ? (
        <img src={headshotUrl!} alt="" className="h-full w-full object-cover object-top" onError={() => setFailed(true)} />
      ) : (
        <span className="flex h-full w-full items-center justify-center bg-hidden font-slab text-fg">
          <span className="font-slab-optical-center">{initials(name)}</span>
        </span>
      )}
    </span>
  );
}

function initials(name: string): string {
  return name.trim().split(/\s+/).filter(Boolean).slice(0, 2).map((part) => part[0]?.toUpperCase()).join("") || "?";
}
