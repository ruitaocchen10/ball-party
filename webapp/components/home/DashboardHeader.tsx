import { Bell, Plus, Search } from "lucide-react";
import Link from "next/link";

import { AccountMenu } from "@/components/foundation/ui-kit/AccountMenu";
import { BrandMark } from "@/components/foundation/ui-kit/BrandMark";

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
        <Link href="/" aria-label="Ball Party home" className="flex w-[var(--sidebar-w)] shrink-0 items-center text-fg focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-panel">
          <BrandMark className="h-8 w-8 shrink-0" />
        </Link>
        <form action="/" className="mx-auto w-full max-w-xl" role="search">
          <label className="sr-only" htmlFor="dashboard-search">
            Search social posts
          </label>
          <div className="flex h-10 items-center gap-2.5 bg-surface-raised px-3 ring-1 ring-line ring-inset transition-colors focus-within:ring-fg-muted">
            <Search aria-hidden className="h-4 w-4 shrink-0 text-fg-muted" strokeWidth={1.8} />
            <input
              id="dashboard-search"
              name="q"
              type="search"
              placeholder="Search social posts"
              className="min-w-0 flex-1 bg-transparent font-mono text-xs tracking-[0.02em] text-fg outline-none placeholder:text-fg-muted"
            />
            <kbd className="hidden border border-line px-1.5 py-0.5 font-mono text-[9px] text-fg-muted lg:block">↵</kbd>
          </div>
        </form>

        <div className="flex shrink-0 items-center gap-1.5">
          <Link
            href="/party"
            className="flex h-10 items-center gap-2 bg-panel px-3.5 font-mono text-[10px] font-bold tracking-[0.12em] text-panel-fg uppercase transition-colors hover:bg-[#fffdf7] focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-panel"
          >
            <Plus aria-hidden className="h-4 w-4" strokeWidth={2} />
            <span className="hidden lg:inline">Start a party</span>
          </Link>
          <button
            type="button"
            aria-label="Notifications"
            title="Notifications are coming soon"
            className="flex h-10 w-10 items-center justify-center text-fg-muted transition-colors hover:text-fg focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-panel"
          >
            <Bell aria-hidden className="h-[18px] w-[18px]" strokeWidth={1.6} />
          </button>
          {displayName ? (
            <AccountMenu displayName={displayName} email={email} avatarUrl={avatarUrl} compact />
          ) : (
            <Link
              href="/login"
              className="ml-1 font-mono text-[10px] font-semibold tracking-[0.12em] text-fg-muted uppercase transition-colors hover:text-fg focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-panel"
            >
              Sign in
            </Link>
          )}
        </div>
      </div>
    </header>
  );
}
