"use client";

import {
  House,
  LogIn,
  Menu,
  MessageCircle,
  PanelLeftClose,
  PanelLeftOpen,
  User,
  Users,
  X,
} from "lucide-react";
import { AnimatePresence, motion } from "motion/react";
import Link from "next/link";
import { usePathname } from "next/navigation";
import { useEffect, useState } from "react";

import { AccountMenu } from "@/components/layout/AccountMenu";
import { BrandMark } from "@/components/ui/BrandMark";
import { drawerBackdrop, drawerPanel } from "@/lib/motion";

/**
 * The app's persistent chrome — a fixed left rail on desktop, a hamburger
 * drawer on mobile. Replaces the old horizontal TopBar: with more sections
 * on the way, a vertical list scales past three items the way a fixed row of
 * chips doesn't, and a rail is where this product's inevitable eventual
 * dedicated mobile app leaves the web experience free to just be ordinary —
 * the mobile treatment here is a standard drawer, not a bespoke design.
 *
 * The rail is `fixed`, so it takes no flow space; every page's <main> reserves
 * room for it with `md:ml-[var(--sidebar-w)]` (see globals.css). That var,
 * not React state, is the bridge — <main> lives in a sibling server component
 * and can't read this component's state directly.
 *
 * Collapse state persists to localStorage and is mirrored onto a
 * `data-sidebar-collapsed` attribute on <html>, which is what both
 * `--sidebar-w` and the no-flash script in app/layout.tsx key off of.
 */
export function Sidebar({
  displayName,
  email = null,
  avatarUrl = null,
}: {
  displayName?: string | null;
  email?: string | null;
  avatarUrl?: string | null;
}) {
  const pathname = usePathname();
  const [collapsed, setCollapsed] = useState(false);
  const [drawerOpen, setDrawerOpen] = useState(false);

  // Adopts whatever the no-flash script already stamped onto <html> before
  // paint, so mounting here never causes a second, contradicting flash. Can
  // only run client-side (SSR has no document to read), which is exactly why
  // this is a one-time effect rather than a render-time read.
  useEffect(() => {
    // eslint-disable-next-line react-hooks/set-state-in-effect -- reading a DOM attribute on mount, not deriving state from a render value
    setCollapsed(document.documentElement.hasAttribute("data-sidebar-collapsed"));
  }, []);

  // A link inside the drawer is a normal <Link> with no onClick of its own —
  // this is what actually closes the drawer once it's navigated somewhere.
  useEffect(() => {
    // eslint-disable-next-line react-hooks/set-state-in-effect -- reacting to navigation (an external event), not deriving state from a prop
    setDrawerOpen(false);
  }, [pathname]);

  function toggleCollapsed() {
    setCollapsed((was) => {
      const next = !was;
      try {
        localStorage.setItem("sidebar-collapsed", String(next));
      } catch {
        // Private-browsing or a blocked store: the toggle still works for
        // this load, it just won't be remembered next time.
      }
      if (next) document.documentElement.setAttribute("data-sidebar-collapsed", "");
      else document.documentElement.removeAttribute("data-sidebar-collapsed");
      return next;
    });
  }

  return (
    <>
      <MobileTopStrip
        displayName={displayName}
        email={email}
        avatarUrl={avatarUrl}
        onOpenMenu={() => setDrawerOpen(true)}
      />

      <aside
        // Targeted by the body:has() rule in globals.css, which reserves
        // --sidebar-w of body padding only on pages that actually mount a
        // rail — a live match screen (AuctionMatch, SabotageDraftMatch,
        // HigherOrLowerMatch) renders no Sidebar at all, live or final, and
        // must not get a dead gutter carved out of it.
        data-sidebar-rail
        className={`fixed top-0 left-0 z-20 hidden h-dvh flex-col bg-surface-raised ring-1 ring-line ring-inset transition-[width] duration-150 md:flex ${
          collapsed ? "w-18" : "w-60"
        }`}
      >
        <Brand collapsed={collapsed} onToggleCollapsed={toggleCollapsed} />

        <div className="flex-1 overflow-y-auto py-4">
          <NavList pathname={pathname} collapsed={collapsed} />
        </div>

        <div
          // Same horizontal inset as Brand above (px-5 expanded, px-2
          // collapsed) so the avatar lines up with the wordmark/toggle row
          // rather than with the nav rows' own, deeper px-3 + px-3 inset.
          className={`border-t border-line py-4 ${collapsed ? "flex justify-center px-2" : "px-5"}`}
        >
          {displayName ? (
            <AccountMenu
              displayName={displayName}
              email={email}
              avatarUrl={avatarUrl}
              placement="up"
              compact={collapsed}
            />
          ) : (
            <SignedOutAccount compact={collapsed} />
          )}
        </div>
      </aside>

      <AnimatePresence>
        {drawerOpen ? (
          <MobileDrawer
            key="drawer"
            pathname={pathname}
            displayName={displayName}
            email={email}
            avatarUrl={avatarUrl}
            onClose={() => setDrawerOpen(false)}
          />
        ) : null}
      </AnimatePresence>
    </>
  );
}

const FOCUS =
  "focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-panel";

const NAV_ITEMS = [
  { href: "/", label: "Home", Icon: House },
  { href: "/party", label: "Party", Icon: Users },
  { href: "/solo", label: "Solo", Icon: User },
  // Dimmed by default, same as before: a real destination — the page it
  // lands on tells the truth about it being unbuilt — but not one the nav
  // should promise at full strength yet.
  { href: "/social", label: "Social", Icon: MessageCircle, muted: true },
];

/**
 * Wordmark plus the collapse toggle, sharing one row: expanded, the button
 * sits beside the logo; collapsed, there's no room for both, so the button
 * takes the logo's own spot rather than getting a row of its own further
 * down — collapsing the rail is squarely about this row, not a separate
 * setting.
 */
function Brand({
  collapsed,
  onToggleCollapsed,
}: {
  collapsed: boolean;
  onToggleCollapsed: () => void;
}) {
  return (
    <div
      className={`flex shrink-0 border-b border-line py-4 ${
        collapsed ? "flex-col items-center gap-3 px-2" : "items-center justify-between px-5"
      }`}
    >
      <Link
        href="/"
        aria-label="Ball Party"
        className={`flex items-center gap-2 text-fg ${FOCUS}`}
      >
        <BrandMark className="h-7 w-7 shrink-0" />
        {collapsed ? null : (
          <span className="font-slab text-[22px] leading-none uppercase">Ball Party</span>
        )}
      </Link>
      <button
        type="button"
        onClick={onToggleCollapsed}
        aria-label={collapsed ? "Expand sidebar" : "Collapse sidebar"}
        className={`flex h-8 w-8 shrink-0 items-center justify-center text-fg-muted transition-colors hover:text-fg ${FOCUS}`}
      >
        {collapsed ? (
          <PanelLeftOpen className="h-[18px] w-[18px]" strokeWidth={1.5} />
        ) : (
          <PanelLeftClose className="h-[18px] w-[18px]" strokeWidth={1.5} />
        )}
      </button>
    </div>
  );
}

/** Shared between the desktop rail and the mobile drawer so the two never drift. */
function NavList({ pathname, collapsed }: { pathname: string; collapsed: boolean }) {
  return (
    <nav aria-label="Sections" className="flex flex-col gap-1 px-3">
      {NAV_ITEMS.map(({ href, label, Icon, muted }) => {
        const active = pathname === href;
        return (
          <Link
            key={href}
            href={href}
            className={`flex items-center gap-3 px-3 py-2.5 font-mono text-xs font-semibold tracking-[0.03em] transition-colors ${FOCUS} ${
              collapsed ? "justify-center" : ""
            } ${
              active
                ? "bg-panel text-panel-fg"
                : muted
                  ? "text-fg-muted hover:text-fg"
                  : "text-fg hover:text-fg-muted"
            }`}
          >
            <Icon className="h-[18px] w-[18px] shrink-0" strokeWidth={1.5} />
            <span className={collapsed ? "sr-only" : ""}>{label}</span>
          </Link>
        );
      })}
    </nav>
  );
}

/**
 * The unauthenticated rail state. Kept separate from AccountMenu so each
 * auth state owns its own layout, same split as before — stacked instead of
 * side-by-side now that it lives in a column instead of a row.
 */
function SignedOutAccount({ compact }: { compact: boolean }) {
  if (compact) {
    return (
      <Link
        href="/login"
        aria-label="Sign in"
        className={`flex h-9 w-9 items-center justify-center bg-panel text-panel-fg ${FOCUS}`}
      >
        <LogIn className="h-[16px] w-[16px]" strokeWidth={1.5} />
      </Link>
    );
  }

  return (
    <div className="flex flex-col gap-2">
      <Link
        href="/signup"
        className={`flex h-9 items-center justify-center bg-panel px-3.5 font-mono text-[10px] font-bold tracking-[0.13em] text-panel-fg uppercase transition-colors hover:bg-[#fffdf7] ${FOCUS}`}
      >
        Sign up
      </Link>
      <Link
        href="/login"
        className={`flex h-8 items-center justify-center font-mono text-[10px] tracking-[0.13em] text-fg-muted uppercase transition-colors hover:text-fg ${FOCUS}`}
      >
        Sign in
      </Link>
    </div>
  );
}

/**
 * The only chrome visible on a phone by default: brand, a hamburger that
 * opens the same nav as the desktop rail, and a compact account trigger.
 * Sticky rather than fixed so it still occupies flow space — <main> needs no
 * mobile-specific offset because of it, the same way the old TopBar worked.
 */
function MobileTopStrip({
  displayName,
  email,
  avatarUrl,
  onOpenMenu,
}: {
  displayName?: string | null;
  email?: string | null;
  avatarUrl?: string | null;
  onOpenMenu: () => void;
}) {
  return (
    <header className="sticky top-0 z-10 flex items-center justify-between bg-surface px-4 py-3 md:hidden">
      <button
        type="button"
        onClick={onOpenMenu}
        aria-label="Open menu"
        className={`flex h-9 w-9 items-center justify-center bg-surface-raised text-fg ring-1 ring-line ring-inset ${FOCUS}`}
      >
        <Menu className="h-[18px] w-[18px]" strokeWidth={1.5} />
      </button>

      <Link
        href="/"
        aria-label="Ball Party"
        className={`flex items-center gap-1.5 text-fg ${FOCUS}`}
      >
        <BrandMark className="h-5 w-5 shrink-0" />
        <span className="font-slab text-[16px] leading-none uppercase">Ball Party</span>
      </Link>

      {displayName ? (
        <AccountMenu displayName={displayName} email={email} avatarUrl={avatarUrl} compact />
      ) : (
        <Link
          href="/login"
          className={`font-mono text-[10px] tracking-[0.13em] text-fg-muted uppercase transition-colors hover:text-fg ${FOCUS}`}
        >
          Sign in
        </Link>
      )}
    </header>
  );
}

function MobileDrawer({
  pathname,
  displayName,
  email,
  avatarUrl,
  onClose,
}: {
  pathname: string;
  displayName?: string | null;
  email?: string | null;
  avatarUrl?: string | null;
  onClose: () => void;
}) {
  // Escape closes it, and the drawer holds the page still behind it — a
  // background scroll under an open drawer reads as the drawer not really
  // being modal.
  useEffect(() => {
    function onKeyDown(event: KeyboardEvent) {
      if (event.key === "Escape") onClose();
    }
    document.addEventListener("keydown", onKeyDown);

    const { overflow } = document.body.style;
    document.body.style.overflow = "hidden";
    return () => {
      document.removeEventListener("keydown", onKeyDown);
      document.body.style.overflow = overflow;
    };
  }, [onClose]);

  return (
    <div className="fixed inset-0 z-30 md:hidden">
      <motion.button
        type="button"
        aria-label="Close menu"
        onClick={onClose}
        variants={drawerBackdrop}
        initial="initial"
        animate="animate"
        exit="exit"
        className="absolute inset-0 bg-black/50"
      />

      <motion.div
        variants={drawerPanel}
        initial="initial"
        animate="animate"
        exit="exit"
        className="absolute top-0 left-0 flex h-full w-72 max-w-[85vw] flex-col bg-surface-raised shadow-card"
      >
        <div className="flex h-16 shrink-0 items-center justify-between border-b border-line px-5">
          <Link
            href="/"
            aria-label="Ball Party"
            className={`flex items-center gap-1.5 text-fg ${FOCUS}`}
          >
            <BrandMark className="h-5 w-5 shrink-0" />
            <span className="font-slab text-[17px] leading-none uppercase">Ball Party</span>
          </Link>
          <button
            type="button"
            onClick={onClose}
            aria-label="Close menu"
            className={`flex h-8 w-8 items-center justify-center text-fg-muted transition-colors hover:text-fg ${FOCUS}`}
          >
            <X className="h-[16px] w-[16px]" strokeWidth={1.5} />
          </button>
        </div>

        <div className="flex-1 overflow-y-auto py-4">
          <NavList pathname={pathname} collapsed={false} />
        </div>

        <div className="border-t border-line px-5 py-3">
          {displayName ? (
            <AccountMenu displayName={displayName} email={email} avatarUrl={avatarUrl} placement="up" />
          ) : (
            <SignedOutAccount compact={false} />
          )}
        </div>
      </motion.div>
    </div>
  );
}
