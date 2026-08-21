import Link from "next/link";

import { AccountMenu } from "@/components/layout/AccountMenu";

/**
 * The app's persistent chrome — three floating groups on a scrim the same
 * color as the page, rather than one hard-edged bar. The brand sits bare on
 * the left, the way a wordmark does when nothing is boxing it in; the
 * sections nav and the account cluster each get their own chip, so the row
 * still reads as separate objects rather than one continuous surface with
 * items pinned to either end.
 *
 * The scrim carries no border and matches `--surface` exactly, so it
 * occludes content scrolling underneath (this is `sticky`, so without it
 * every page's content scrolled straight through the empty space around the
 * chips) without itself being a visible object — only the chips, sitting on
 * top of it, are.
 *
 * A 3-column grid rather than flex + spacer: that's what keeps the center
 * chip dead-center regardless of how wide the brand or the account cluster
 * are, instead of drifting toward whichever side is lighter.
 *
 * The bar spans the window but its contents do not: the row sits in the same
 * max-w-7xl container the pages use, so the brand shares a left edge with the
 * page's first heading instead of floating out in the margin.
 */
export function TopBar({ displayName }: { displayName?: string | null }) {
  return (
    <header className="sticky top-0 z-10 bg-surface py-3">
      <div className="mx-auto grid w-full max-w-7xl grid-cols-[1fr_auto_1fr] items-center gap-x-4 px-4 sm:px-6 lg:px-8">
        <Brand />
        <SectionsNav />
        <Account displayName={displayName} />
      </div>
    </header>
  );
}

const FOCUS =
  "focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-panel";

/** A chip: the shared surface every group but the brand sits on, so the three
 *  read as the same family of object even though only two of them box. */
const CHIP = "flex items-center bg-surface-raised shadow-card ring-1 ring-line ring-inset";

function Brand() {
  return (
    <Link
      href="/"
      className={`shrink-0 justify-self-start font-slab text-[17px] leading-none -skew-x-7 text-fg uppercase ${FOCUS}`}
    >
      Ball Party
    </Link>
  );
}

/**
 * Party, Solo and Social, promoted from the home page's sections into global
 * chrome — the same names used there (see ColumnHead and ActionStrip in
 * app/page.tsx), so the bar isn't introducing a second vocabulary for the
 * same things. All three point at home-page anchors, since none has its own
 * route yet.
 *
 * Party and Solo are both real destinations today — starting or joining a
 * room, and Higher or Lower's solo floor — so both read at full strength.
 * Social stays visibly the lesser of the three: it is real enough to link
 * to — the section it lands on tells the truth about it being unbuilt — but
 * dimming it here keeps the nav from promising a live destination the home
 * page itself doesn't promise.
 */
function SectionsNav() {
  return (
    <nav aria-label="Sections" className={`${CHIP} justify-self-center gap-x-5 px-4 py-2`}>
      <Link
        href="/#party-heading"
        className={`font-mono text-[10px] tracking-[0.13em] text-fg uppercase transition-colors hover:text-fg-muted ${FOCUS}`}
      >
        Party
      </Link>
      <Link
        href="/#solo-heading"
        className={`font-mono text-[10px] tracking-[0.13em] text-fg uppercase transition-colors hover:text-fg-muted ${FOCUS}`}
      >
        Solo
      </Link>
      <Link
        href="/#social-heading"
        className={`font-mono text-[10px] tracking-[0.13em] text-fg-muted uppercase transition-colors hover:text-fg ${FOCUS}`}
      >
        Social
      </Link>
    </nav>
  );
}

function Account({ displayName }: { displayName?: string | null }) {
  return (
    <div className="justify-self-end">
      {displayName ? <AccountMenu displayName={displayName} /> : <SignedOutAccount />}
    </div>
  );
}

/**
 * The unauthenticated top-bar state. Kept separate from the account menu so
 * each auth state owns its own layout and responsive visibility rules.
 */
function SignedOutAccount() {
  return (
    <div className={`${CHIP} gap-x-4 py-1.5 pr-1.5 pl-3.5`}>
      <Link
        href="/login"
        className={`hidden font-mono text-[10px] tracking-[0.13em] text-fg-muted uppercase transition-colors hover:text-fg sm:block ${FOCUS}`}
      >
        Sign in
      </Link>
      <Link
        href="/signup"
        className={`flex h-8 items-center justify-center bg-panel px-3.5 font-mono text-[10px] font-bold tracking-[0.13em] text-panel-fg uppercase transition-colors hover:bg-[#fffdf7] ${FOCUS}`}
      >
        Sign up
      </Link>
    </div>
  );
}
