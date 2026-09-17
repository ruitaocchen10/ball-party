"use client";

import {
  House,
  LogIn,
  Menu,
  MessageSquarePlus,
  PanelLeftClose,
  PanelLeftOpen,
  Play,
  Users,
  X,
} from "lucide-react";
import { AnimatePresence, motion } from "motion/react";
import Link from "next/link";
import { usePathname } from "next/navigation";
import { useEffect, useState } from "react";

import { AccountMenu } from "@/components/foundation/ui-kit/AccountMenu";
import { FeedbackModal } from "@/components/feedback/FeedbackModal";
import { BrandMark } from "@/components/foundation/ui-kit/BrandMark";
import { GAMES, type Game } from "@/lib/platform/orchestration/catalog";
import { playSolo } from "@/lib/platform/lobbies/actions";
import { SOLO_SIGN_UP_HREF } from "@/lib/platform/lobbies/hosting";
import { drawerBackdrop, drawerPanel } from "@/lib/foundation/ui-kit/motion";

/** The solo-playable games, in catalog order — everything the Solo games
 *  section lists. Just Higher or Lower today; a second live+solo game shows
 *  up here with no further change. */
const SOLO_GAMES = GAMES.filter((game) => game.solo && game.status === "live");

/**
 * The app's persistent navigation — a fixed left rail below the desktop top
 * bar, and a hamburger drawer on mobile. A vertical list scales past three
 * sections without crowding the global search and utility controls above it.
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
  canPlaySolo = false,
}: {
  displayName?: string | null;
  email?: string | null;
  avatarUrl?: string | null;
  /** Whether the viewer can start a solo game from this rail right now —
   *  guests included, the same floor `soloGames()`/`playSolo` use, just
   *  evaluated per page since Sidebar has no session of its own to read. */
  canPlaySolo?: boolean;
}) {
  const pathname = usePathname();
  const [collapsed, setCollapsed] = useState(false);
  const [drawerOpen, setDrawerOpen] = useState(false);
  const [feedbackOpen, setFeedbackOpen] = useState(false);

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
        className={`fixed top-[68px] left-0 z-20 hidden h-[calc(100dvh-68px)] flex-col bg-surface-raised ring-1 ring-line ring-inset transition-[width] duration-150 md:flex ${
          collapsed ? "w-20" : "w-68"
        }`}
      >
        <SidebarToggle collapsed={collapsed} onToggleCollapsed={toggleCollapsed} />

        <div className="flex-1 overflow-y-auto pt-5">
          <NavList pathname={pathname} collapsed={collapsed} />

          {SOLO_GAMES.length > 0 ? (
            <>
              <div className="ml-3 mr-8 my-3 border-t border-line" />
              <SoloGamesNav collapsed={collapsed} canPlaySolo={canPlaySolo} />
            </>
          ) : null}

          <div className="ml-3 mr-8 my-3 border-t border-line" />

          <div className="px-3 pb-3">
            <FeedbackButton compact={collapsed} onOpen={() => setFeedbackOpen(true)} />
          </div>
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
            canPlaySolo={canPlaySolo}
            onClose={() => setDrawerOpen(false)}
            onOpenFeedback={() => {
              setDrawerOpen(false);
              setFeedbackOpen(true);
            }}
          />
        ) : null}
      </AnimatePresence>

      {feedbackOpen ? <FeedbackModal route={pathname} onClose={() => setFeedbackOpen(false)} /> : null}
    </>
  );
}

const FOCUS =
  "focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-panel";

function FeedbackButton({ compact, onOpen }: { compact: boolean; onOpen: () => void }) {
  return (
    <button
      type="button"
      onClick={onOpen}
      className={`flex w-full items-center gap-3.5 px-3 py-2.5 font-mono text-sm font-semibold tracking-[0.03em] text-fg transition-colors hover:text-fg-muted ${FOCUS} ${
        compact ? "justify-center" : ""
      }`}
    >
      <MessageSquarePlus className="h-5 w-5 shrink-0" strokeWidth={1.5} />
      <span className={compact ? "sr-only" : ""}>Feedback</span>
    </button>
  );
}

const NAV_ITEMS = [
  { href: "/", label: "Home", Icon: House },
  { href: "/party", label: "Party", Icon: Users },
];

/**
 * Reddit-style edge control: it straddles the rail's outer border instead of
 * consuming a row inside the navigation. Brand identity belongs in the top
 * bar, where it remains visible even when this rail is collapsed.
 */
function SidebarToggle({
  collapsed,
  onToggleCollapsed,
}: {
  collapsed: boolean;
  onToggleCollapsed: () => void;
}) {
  return (
    <button
      type="button"
      onClick={onToggleCollapsed}
      aria-label={collapsed ? "Expand sidebar" : "Collapse sidebar"}
      className={`absolute top-[23px] -right-[17px] z-10 flex h-[34px] w-[34px] items-center justify-center rounded-full border border-fg-muted bg-surface text-fg transition-colors hover:bg-surface-raised focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-panel ${FOCUS}`}
    >
      {collapsed ? (
        <PanelLeftOpen className="h-[18px] w-[18px]" strokeWidth={1.5} />
      ) : (
        <PanelLeftClose className="h-[18px] w-[18px]" strokeWidth={1.5} />
      )}
    </button>
  );
}

/** Shared between the desktop rail and the mobile drawer so the two never drift. */
function NavList({ pathname, collapsed }: { pathname: string; collapsed: boolean }) {
  return (
    <nav aria-label="Sections" className="flex flex-col gap-1 px-3 pr-8">
      {NAV_ITEMS.map(({ href, label, Icon }) => {
        const active = pathname === href;
        return (
          <Link
            key={href}
            href={href}
            className={`flex items-center gap-3.5 px-3 py-2.5 font-mono text-sm font-semibold tracking-[0.03em] transition-colors ${FOCUS} ${
              collapsed ? "justify-center" : ""
            } ${
              active
                ? "bg-panel text-panel-fg"
                : "text-fg hover:text-fg-muted"
            }`}
          >
            <Icon className="h-5 w-5 shrink-0" strokeWidth={1.5} />
            <span className={collapsed ? "sr-only" : ""}>{label}</span>
          </Link>
        );
      })}
    </nav>
  );
}

/**
 * The rail's second nav section: every solo-playable game, one tap from a
 * live match — no detour through a grid page to click a second "Play solo"
 * there. Shared between the desktop rail and the mobile drawer, same as
 * NavList, so the two can't drift.
 */
function SoloGamesNav({ collapsed, canPlaySolo }: { collapsed: boolean; canPlaySolo: boolean }) {
  return (
    <div className="px-3 pr-8">
      <Link
        href="/solo"
        className={`block px-3 pb-1.5 font-mono text-[10px] tracking-[0.15em] text-fg-muted uppercase transition-colors hover:text-fg ${FOCUS} ${
          collapsed ? "sr-only" : ""
        }`}
      >
        Solo games
      </Link>
      <nav aria-label="Solo games" className="flex flex-col gap-1">
        {SOLO_GAMES.map((game) => (
          <SoloGameLink key={game.slug} game={game} collapsed={collapsed} canPlaySolo={canPlaySolo} />
        ))}
      </nav>
    </div>
  );
}

const NAV_ITEM_CLASSES = (collapsed: boolean) =>
  `flex items-center gap-3.5 px-3 py-2.5 font-mono text-sm font-semibold tracking-[0.03em] text-fg transition-colors hover:text-fg-muted ${FOCUS} ${
    collapsed ? "justify-center" : ""
  }`;

/**
 * One solo game's entry: a form that starts a fresh run via `playSolo` when
 * the viewer can play (a signed-in button beats a link nobody can act on
 * twice in a row the same way — each click deals a new match), or a sign-up
 * link when they can't. Styled to match NavList's links exactly, since this
 * reads as a continuation of the same nav rather than a distinct widget.
 */
function SoloGameLink({
  game,
  collapsed,
  canPlaySolo,
}: {
  game: Game;
  collapsed: boolean;
  canPlaySolo: boolean;
}) {
  const label = game.name.join(" ");

  if (!canPlaySolo) {
    return (
      <Link href={SOLO_SIGN_UP_HREF} className={NAV_ITEM_CLASSES(collapsed)}>
        <Play className="h-5 w-5 shrink-0" strokeWidth={1.5} />
        <span className={collapsed ? "sr-only" : ""}>{label}</span>
      </Link>
    );
  }

  return (
    <form action={playSolo}>
      <input type="hidden" name="game" value={game.match ?? ""} />
      <button type="submit" className={`w-full cursor-pointer ${NAV_ITEM_CLASSES(collapsed)}`}>
        <Play className="h-5 w-5 shrink-0" strokeWidth={1.5} />
        <span className={collapsed ? "sr-only" : ""}>{label}</span>
      </button>
    </form>
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
        <LogIn className="h-[18px] w-[18px]" strokeWidth={1.5} />
      </Link>
    );
  }

  return (
    <div className="flex flex-col gap-2">
      <Link
        href="/signup"
        className={`flex h-9 items-center justify-center bg-panel px-3.5 font-mono text-xs font-bold tracking-[0.13em] text-panel-fg uppercase transition-colors hover:bg-[#fffdf7] ${FOCUS}`}
      >
        Sign up
      </Link>
      <Link
        href="/login"
        className={`flex h-8 items-center justify-center font-mono text-xs tracking-[0.13em] text-fg-muted uppercase transition-colors hover:text-fg ${FOCUS}`}
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
    <header className="sticky top-0 z-10 flex items-center justify-between bg-surface px-4 py-2.5 md:hidden">
      <button
        type="button"
        onClick={onOpenMenu}
        aria-label="Open menu"
        className={`flex h-9 w-9 items-center justify-center bg-surface-raised text-fg ring-1 ring-line ring-inset ${FOCUS}`}
      >
        <Menu className="h-5 w-5" strokeWidth={1.5} />
      </button>

      <Link href="/" aria-label="Ball Party" className={`flex items-center text-fg ${FOCUS}`}>
        <BrandMark className="h-6 w-6 shrink-0" />
      </Link>

      {displayName ? (
        <AccountMenu displayName={displayName} email={email} avatarUrl={avatarUrl} compact />
      ) : (
        <Link
          href="/login"
          className={`font-mono text-xs tracking-[0.13em] text-fg-muted uppercase transition-colors hover:text-fg ${FOCUS}`}
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
  canPlaySolo,
  onClose,
  onOpenFeedback,
}: {
  pathname: string;
  displayName?: string | null;
  email?: string | null;
  avatarUrl?: string | null;
  canPlaySolo: boolean;
  onClose: () => void;
  onOpenFeedback: () => void;
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
        className="absolute top-0 left-0 flex h-full w-80 max-w-[85vw] flex-col bg-surface-raised shadow-card"
      >
        <div className="flex h-16 shrink-0 items-center justify-between border-b border-line px-5">
          <Link href="/" aria-label="Ball Party" className={`flex items-center text-fg ${FOCUS}`}>
            <BrandMark className="h-6 w-6 shrink-0" />
          </Link>
          <button
            type="button"
            onClick={onClose}
            aria-label="Close menu"
            className={`flex h-8 w-8 items-center justify-center text-fg-muted transition-colors hover:text-fg ${FOCUS}`}
          >
            <X className="h-[18px] w-[18px]" strokeWidth={1.5} />
          </button>
        </div>

        <div className="flex-1 overflow-y-auto py-3">
          <NavList pathname={pathname} collapsed={false} />

          {SOLO_GAMES.length > 0 ? (
            <>
              <div className="ml-3 mr-8 my-3 border-t border-line" />
              <SoloGamesNav collapsed={false} canPlaySolo={canPlaySolo} />
            </>
          ) : null}
        </div>

        <div className="border-t border-line px-3 py-3">
          <FeedbackButton compact={false} onOpen={onOpenFeedback} />
        </div>

        <div className="border-t border-line px-5 py-2.5">
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
