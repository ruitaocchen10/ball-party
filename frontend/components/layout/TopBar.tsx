import Link from "next/link";

import { AccountMenu } from "@/components/layout/AccountMenu";

/**
 * The app's persistent chrome. A bar rather than a rail: there is nowhere to
 * navigate to — only a brand and who you are — and the screens underneath want
 * their full width for the games.
 *
 * Deliberately thin on function. Joining a room used to live here; it moved
 * into the home page (see components/home/JoinRoom.tsx), where it can sit
 * beside "Start a room" at full size instead of being squeezed into a bar that
 * every other screen also carries.
 *
 * One rendering at every size — with the code field gone, nothing here needs
 * to wrap.
 *
 * The bar spans the window but its contents do not: the row sits in the same
 * max-w-5xl container the pages use, so the brand shares a left edge with the
 * page's first heading instead of floating out in the margin.
 */
export function TopBar({ displayName }: { displayName?: string | null }) {
  return (
    <header className="sticky top-0 z-10 border-b border-line bg-surface/92 backdrop-blur-sm">
      <div className="mx-auto flex h-14 w-full max-w-7xl items-center gap-x-5 px-4 sm:px-6 lg:px-8">
        <Brand />
        <div className="flex-1" />
        <Account displayName={displayName} />
      </div>
    </header>
  );
}

const FOCUS =
  "focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-panel";

function Brand() {
  return (
    <Link
      href="/"
      className={`shrink-0 rounded-[2px] font-slab text-[17px] leading-none -skew-x-7 text-fg uppercase ${FOCUS}`}
    >
      Ball Party
    </Link>
  );
}

function Account({ displayName }: { displayName?: string | null }) {
  if (displayName) return <AccountMenu displayName={displayName} />;

  return <SignedOutAccount />;
}

/**
 * The unauthenticated top-bar state. Kept separate from the account menu so
 * each auth state owns its own layout and responsive visibility rules.
 */
function SignedOutAccount() {
  return (
    <div className="flex shrink-0 items-center gap-4">
      <Link
        href="/login"
        className={`hidden rounded-[2px] font-mono text-[10px] tracking-[0.13em] text-fg-muted uppercase transition-colors hover:text-fg sm:block ${FOCUS}`}
      >
        Sign in
      </Link>
      <Link
        href="/signup"
        className={`flex h-8 items-center justify-center rounded-[3px] bg-panel px-3.5 font-mono text-[10px] font-bold tracking-[0.13em] text-panel-fg uppercase transition-colors hover:bg-[#fffdf7] ${FOCUS}`}
      >
        Sign up
      </Link>
    </div>
  );
}
