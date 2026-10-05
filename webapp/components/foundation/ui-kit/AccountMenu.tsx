"use client";

import { ChevronDown } from "lucide-react";
import { AnimatePresence, motion } from "motion/react";
import Link from "next/link";
import { useEffect, useRef, useState } from "react";

import { signOut } from "@/lib/foundation/identity/actions";
import { GeneratedAvatar } from "@/components/foundation/identity/GeneratedAvatar";
import { dropdown, dropdownUp } from "@/lib/foundation/ui-kit/motion";

/**
 * The signed-in account control in the top bar: the avatar chip opens a menu of
 * everything that belongs to "you" rather than to the room you're in.
 *
 * The menu is a cream panel because that's what this product does with things
 * that matter — the chip is already a lit object, and opening it expands into a
 * larger one rather than into some other kind of surface.
 *
 * It also earns back space on small screens. The display name and sign-out used
 * to sit in the bar beside the chip, which left a phone with brand, room code,
 * name and a sign-out button competing for one row. Both live in here now.
 *
 * `placement` flips the menu to open upward and anchor left rather than
 * down and right — the sidebar pins this control to the bottom-left of a
 * rail, where the default top-right-anchored menu would clip off the bottom
 * of the viewport. `compact` drops the name/email stack, the chevron, and
 * the trigger's own box so it's just the avatar, for the collapsed rail and
 * the mobile strip, where the `lg:` breakpoint alone can't tell the
 * difference between "narrow viewport" and "narrow because the rail is
 * collapsed."
 */
export function AccountMenu({
  displayName,
  email = null,
  avatarUrl = null,
  placement = "down",
  compact = false,
}: {
  displayName: string;
  email?: string | null;
  avatarUrl?: string | null;
  placement?: "down" | "up";
  compact?: boolean;
}) {
  const [open, setOpen] = useState(false);
  const [imageFailed, setImageFailed] = useState(false);
  const [seenAvatarUrl, setSeenAvatarUrl] = useState(avatarUrl);
  if (avatarUrl !== seenAvatarUrl) {
    setSeenAvatarUrl(avatarUrl);
    setImageFailed(false);
  }
  const rootRef = useRef<HTMLDivElement>(null);
  const triggerRef = useRef<HTMLButtonElement>(null);
  const menuRef = useRef<HTMLDivElement>(null);

  function items(): HTMLElement[] {
    return Array.from(menuRef.current?.querySelectorAll<HTMLElement>('[role="menuitem"]') ?? []);
  }

  // Anything that means "I'm done with this menu" closes it: a press outside,
  // focus leaving it (tabbing past the last item), or Escape. Escape is the
  // only one that moves focus back to the trigger — the others are already
  // taking the user somewhere of their own choosing.
  useEffect(() => {
    if (!open) return;

    function onPointerDown(event: PointerEvent) {
      if (!rootRef.current?.contains(event.target as Node)) setOpen(false);
    }

    function onKeyDown(event: KeyboardEvent) {
      if (event.key !== "Escape") return;
      setOpen(false);
      triggerRef.current?.focus();
    }

    document.addEventListener("pointerdown", onPointerDown);
    document.addEventListener("keydown", onKeyDown);
    return () => {
      document.removeEventListener("pointerdown", onPointerDown);
      document.removeEventListener("keydown", onKeyDown);
    };
  }, [open]);

  // Opening moves focus to the first item, per the menu button pattern. A mouse
  // click won't paint a focus ring for it — the highlight below is :focus, not
  // :focus-visible, precisely so arrow keys have something to show.
  useEffect(() => {
    if (open) items()[0]?.focus();
  }, [open]);

  function moveFocus(delta: number) {
    const all = items();
    if (all.length === 0) return;
    const current = all.findIndex((item) => item === document.activeElement);
    // Wraps in both directions, and an unfocused menu enters at whichever end
    // the key implies: -1 + 1 = 0 going down, -1 - 1 wraps to the last.
    all[(current + delta + all.length) % all.length]!.focus();
  }

  function onMenuKeyDown(event: React.KeyboardEvent) {
    if (event.key === "ArrowDown") {
      event.preventDefault();
      moveFocus(1);
    } else if (event.key === "ArrowUp") {
      event.preventDefault();
      moveFocus(-1);
    }
  }

  return (
    <div
      ref={rootRef}
      className="relative shrink-0"
      onBlur={(event) => {
        if (!rootRef.current?.contains(event.relatedTarget as Node | null)) setOpen(false);
      }}
    >
      <button
        ref={triggerRef}
        type="button"
        aria-haspopup="menu"
        aria-expanded={open}
        onClick={() => setOpen((wasOpen) => !wasOpen)}
        onKeyDown={(event) => {
          if (event.key !== "ArrowDown") return;
          event.preventDefault();
          setOpen(true);
        }}
        className={`flex cursor-pointer items-center gap-2.5 transition-colors focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-panel ${
          compact ? "" : "w-full"
        }`}
      >
        <span
          aria-hidden
          className="flex h-10 w-10 shrink-0 items-center justify-center overflow-hidden rounded-full bg-panel font-slab text-base leading-none text-panel-fg shadow-card"
        >
          {avatarUrl && !imageFailed ? (
            <motion.img
              src={avatarUrl}
              alt=""
              onError={() => setImageFailed(true)}
              className="h-full w-full object-cover"
            />
          ) : (
            <GeneratedAvatar name={displayName} size={40} />
          )}
        </span>
        {!compact ? (
          <span className="min-w-0 flex-1 text-left">
            <span className="block truncate font-mono text-sm font-semibold tracking-[0.06em] text-fg uppercase">
              {displayName}
            </span>
            {email ? (
              <span className="mt-0.5 block truncate font-mono text-xs tracking-[0.02em] text-fg-muted normal-case">
                {email}
              </span>
            ) : null}
          </span>
        ) : null}
        {!compact ? (
          <ChevronDown
            aria-hidden
            className={`h-4 w-4 shrink-0 text-fg-muted transition-transform ${open ? "rotate-180" : ""}`}
            strokeWidth={1.5}
          />
        ) : null}
        <span className="sr-only">Account menu</span>
      </button>

      <AnimatePresence>
        {open ? (
          <motion.div
            key="menu"
            ref={menuRef}
            role="menu"
            aria-label="Account"
            onKeyDown={onMenuKeyDown}
            variants={placement === "up" ? dropdownUp : dropdown}
            initial="initial"
            animate="animate"
            exit="exit"
            style={{ transformOrigin: placement === "up" ? "bottom left" : "top right" }}
            className={`absolute z-20 w-56 overflow-hidden rounded-card bg-panel text-panel-fg shadow-card ${
              placement === "up" ? "bottom-full left-0 mb-2" : "top-full right-0 mt-2"
            }`}
          >
            {/* The bar hides the name/email below `lg` and whenever the trigger
                is compact, so for most phones and the collapsed rail this is
                the only place either appears. Not a menu item — it isn't an
                action. */}
            <div className="border-b border-panel-fg/10 px-3 pt-2.5 pb-2.5">
              <p className="truncate font-slab text-[20px] leading-[1.1] uppercase">{displayName}</p>
              {email ? <p className="mt-1 truncate font-mono text-[10px] tracking-[0.02em] text-panel-muted">{email}</p> : null}
            </div>

            <MenuLink href="/profile">View profile</MenuLink>
            <MenuLink href="/settings">Settings</MenuLink>

            <form action={signOut} className="border-t border-panel-fg/10">
              <button type="submit" role="menuitem" className={ITEM}>
                Sign out
              </button>
            </form>
          </motion.div>
        ) : null}
      </AnimatePresence>
    </div>
  );
}

const ITEM =
  "block w-full cursor-pointer px-3 py-4 text-left type-label " +
  "transition-colors hover:bg-panel-shade focus:bg-panel-shade focus:outline-none";

function MenuLink({ href, children }: { href: string; children: React.ReactNode }) {
  return (
    <Link href={href} role="menuitem" className={ITEM}>
      {children}
    </Link>
  );
}
