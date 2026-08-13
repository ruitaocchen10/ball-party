"use client";

import { useState } from "react";

export function ProfileAvatar({ name, avatarUrl }: { name: string; avatarUrl: string | null }) {
  const [imageFailed, setImageFailed] = useState(false);

  if (avatarUrl && !imageFailed) {
    // Avatar URLs are user-provided hostnames, so Next's allowlisted image
    // optimizer cannot be used here. An error returns to the initials card.
    return <img src={avatarUrl} alt="" onError={() => setImageFailed(true)} className="h-20 w-20 shrink-0 rounded-full border-4 border-panel object-cover shadow-card" />; // eslint-disable-line @next/next/no-img-element
  }

  return <div aria-hidden className="grid h-20 w-20 shrink-0 place-items-center rounded-full border-4 border-panel bg-hidden font-slab text-2xl -skew-x-7 text-panel shadow-card">{initials(name)}</div>;
}

function initials(name: string) { return name.trim().split(/\s+/).filter(Boolean).slice(0, 2).map((part) => part[0]?.toUpperCase()).join("") || "?"; }
