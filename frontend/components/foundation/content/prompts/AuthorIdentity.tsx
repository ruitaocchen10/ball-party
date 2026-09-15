"use client";

import { useState } from "react";

import { initials } from "@/lib/foundation/content/prompts/logic";

/** A compact author avatar and display name for Huddle conversation surfaces. */
export function AuthorIdentity({
  name,
  avatarUrl = null,
  className = "",
}: {
  name: string;
  avatarUrl?: string | null;
  className?: string;
}) {
  return (
    <div className={`flex min-w-0 items-center gap-2 ${className}`}>
      <AuthorAvatar name={name} avatarUrl={avatarUrl} />
      <div className="min-w-0 leading-none">
        <p className="truncate font-mono text-base font-bold text-fg">{name}</p>
        <p className="mt-1 font-mono text-[10px] tracking-[0.08em] text-fg-muted uppercase">Rookie</p>
      </div>
    </div>
  );
}

export function AuthorAvatar({
  name,
  avatarUrl = null,
  className = "h-10 w-10",
}: {
  name: string;
  avatarUrl?: string | null;
  className?: string;
}) {
  const [failed, setFailed] = useState(false);
  const showImage = Boolean(avatarUrl) && !failed;

  return (
    <span className={`inline-flex shrink-0 items-center justify-center overflow-hidden rounded-full bg-panel-fg font-slab text-panel ring-1 ring-line ring-inset ${className}`}>
      {showImage ? (
        // Other comment authors' avatars aren't fetched at all (feed.ts only
        // selects display_name for them) — this only ever fires for the viewer.
        // eslint-disable-next-line @next/next/no-img-element
        <img src={avatarUrl!} alt="" className="h-full w-full object-cover object-top" onError={() => setFailed(true)} />
      ) : (
        initials(name)
      )}
    </span>
  );
}
