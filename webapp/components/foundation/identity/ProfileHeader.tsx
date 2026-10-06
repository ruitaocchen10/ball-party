import type { ReactNode } from "react";

import { ProfileAvatar } from "@/components/foundation/identity/ProfileAvatar";

type ProfileHeaderProps = {
  displayName: string;
  avatarUrl: string | null;
  joinedLabel: string;
  /** A profile owner can supply an edit control; public profiles need not. */
  action?: ReactNode;
};

/**
 * The identity-specific counterpart to PageHeader.
 *
 * It keeps the shared eyebrow, display type, supporting copy, and divider,
 * while owning the avatar-and-action layout that would make PageHeader's
 * otherwise compact interface profile-specific.
 */
export function ProfileHeader({ displayName, avatarUrl, joinedLabel, action }: ProfileHeaderProps) {
  return (
    <header className="w-full border-b border-line pb-5 sm:pb-6">
      <div className="flex flex-col gap-4 sm:flex-row sm:items-center sm:gap-5">
        <ProfileAvatar name={displayName} avatarUrl={avatarUrl} />
        <div className="min-w-0 flex-1">
          <p className="type-label font-semibold text-fg-muted">{joinedLabel}</p>
          <h1 className="mt-1 font-slab text-[34px] leading-none uppercase sm:text-[42px]">{displayName}</h1>
        </div>
        {action ? <div className="shrink-0">{action}</div> : null}
      </div>
    </header>
  );
}
