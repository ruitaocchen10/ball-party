import type { ReactNode } from "react";

import { ProfileAvatar } from "@/components/foundation/identity/ProfileAvatar";

type ProfileHeaderProps = {
  displayName: string;
  avatarUrl: string | null;
  /** Shown as @username under the name when the player has one. */
  username?: string | null;
  /** A small line under the username, for a profile that wants one. */
  joinedLabel?: string;
  /** Buttons under the identity: edit and friends on your own profile, friend actions on another's. */
  action?: ReactNode;
};

/**
 * The identity block of a profile: a large avatar with the name in display
 * type and the username beside it. The profile's buttons sit to the right from
 * `sm` up and drop below on a phone.
 */
export function ProfileHeader({ displayName, avatarUrl, username = null, joinedLabel, action }: ProfileHeaderProps) {
  return (
    <header className="mb-4 flex w-full flex-col gap-5 sm:flex-row sm:items-center sm:gap-6">
      <div className="flex min-w-0 flex-1 items-center gap-4 sm:gap-5">
        <ProfileAvatar name={displayName} avatarUrl={avatarUrl} size={80} />
        <div className="min-w-0 flex-1">
          <h1 className="font-slab text-[34px] leading-none uppercase [overflow-wrap:anywhere] sm:text-[42px]">{displayName}</h1>
          {username ? <p className="mt-0.5 text-base text-fg-muted">@{username}</p> : null}
          {joinedLabel ? <p className="mt-2 type-label text-fg-muted">{joinedLabel}</p> : null}
        </div>
      </div>
      {action ? <div className="flex w-full flex-wrap gap-2 sm:w-auto sm:shrink-0 sm:flex-col">{action}</div> : null}
    </header>
  );
}
