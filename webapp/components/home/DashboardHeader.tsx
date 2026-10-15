import Link from "next/link";

import { AccountMenu } from "@/components/foundation/ui-kit/AccountMenu";
import { NotificationBell } from "@/components/foundation/notifications/NotificationBell";
import { BrandMark } from "@/components/foundation/ui-kit/BrandMark";
import { HuddleSearchField } from "@/components/home/HuddleSearchField";

/**
 * Desktop-only utility bar for Home. Navigation and identity deliberately
 * remain in Sidebar; this is the lightweight, always-available layer for
 * finding a prompt or starting something new.
 */
export function DashboardHeader({
  displayName,
  email,
  avatarUrl,
}: {
  displayName: string | null;
  email: string | null;
  avatarUrl: string | null;
}) {
  return (
    <header className="fixed inset-x-0 top-0 z-30 hidden h-[68px] border-b border-line bg-surface/95 backdrop-blur md:block">
      <div className="flex h-full w-full items-center gap-4 px-5">
        <Link href="/" aria-label="Ball Party home" className="flex w-[var(--sidebar-w)] shrink-0 items-center text-fg focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-fg">
          <BrandMark className="h-8 w-8 shrink-0" />
        </Link>
        <HuddleSearchField />

        <div className="flex shrink-0 items-center gap-1.5">
          {displayName ? <NotificationBell /> : null}
          {displayName ? (
            <AccountMenu displayName={displayName} email={email} avatarUrl={avatarUrl} compact />
          ) : (
            <Link
              href="/login"
              className="ml-1 type-label font-semibold text-fg-muted transition-colors hover:text-fg focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-fg"
            >
              Sign in
            </Link>
          )}
        </div>
      </div>
    </header>
  );
}
