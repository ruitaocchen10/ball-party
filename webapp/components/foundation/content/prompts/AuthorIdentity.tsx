"use client";

import { useState } from "react";

import { GeneratedAvatar } from "@/components/foundation/identity/GeneratedAvatar";

/** A compact author avatar and display name for Huddle conversation surfaces. */
export function AuthorIdentity({
  name,
  avatarUrl = null,
  username = null,
  className = "",
}: {
  name: string;
  avatarUrl?: string | null;
  /** Shown as @username under the name; without one (a guest, or an old row) there is no second line. */
  username?: string | null;
  className?: string;
}) {
  return (
    <div className={`flex min-w-0 items-center gap-2 ${className}`}>
      <AuthorAvatar name={name} avatarUrl={avatarUrl} />
      <div className="min-w-0 leading-none">
        <p className="truncate font-mono text-base font-bold text-fg">{name}</p>
        {username ? <p className="mt-1 truncate type-label text-fg-muted">@{username}</p> : null}
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
        // eslint-disable-next-line @next/next/no-img-element
        <img src={avatarUrl!} alt="" className="h-full w-full object-cover object-top" onError={() => setFailed(true)} />
      ) : (
        <GeneratedAvatar name={name} size={40} className="h-full w-full" />
      )}
    </span>
  );
}
