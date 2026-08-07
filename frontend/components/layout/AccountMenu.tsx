"use client";

import Link from "next/link";
import { useEffect, useRef, useState } from "react";

import { signOut } from "@/lib/auth/actions";

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
 */
export function AccountMenu({ displayName }: { displayName: string }) {
  const [open, setOpen] = useState(false);
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
        className="flex cursor-pointer items-center gap-2.5 rounded-[3px] focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-panel"
      >
        <span
          aria-hidden
          className="flex h-7 w-7 items-center justify-center rounded-[3px] bg-panel font-slab text-xs leading-none -skew-x-7 text-panel-fg shadow-card"
        >
          {initials(displayName)}
        </span>
        <span className="hidden max-w-[15ch] min-w-0 truncate font-mono text-[10px] tracking-[0.11em] text-fg uppercase lg:block">
          {displayName}
        </span>
        <Chevron open={open} />
        <span className="sr-only">Account menu</span>
      </button>

      {open ? (
        <div
          ref={menuRef}
          role="menu"
          aria-label="Account"
          onKeyDown={onMenuKeyDown}
          className="absolute top-full right-0 z-20 mt-2 w-56 overflow-hidden rounded-card bg-panel text-panel-fg shadow-card"
        >
          {/* The bar hides the name below `lg`, so for most phones this is the
              only place it appears. Not a menu item — it isn't an action. */}
          <p className="truncate border-b border-panel-fg/10 px-3 pt-2.5 pb-2.5 font-slab text-[15px] leading-[1.1] -skew-x-7 uppercase">
            {displayName}
          </p>

          <MenuLink href="/profile">View profile</MenuLink>
          <MenuLink href="/settings">Settings</MenuLink>

          <form action={signOut} className="border-t border-panel-fg/10">
            <button type="submit" role="menuitem" className={ITEM}>
              Sign out
            </button>
          </form>
        </div>
      ) : null}
    </div>
  );
}

const ITEM =
  "block w-full cursor-pointer px-3 py-2.5 text-left font-mono text-[10px] tracking-[0.13em] uppercase " +
  "transition-colors hover:bg-panel-shade focus:bg-panel-shade focus:outline-none";

function MenuLink({ href, children }: { href: string; children: React.ReactNode }) {
  return (
    <Link href={href} role="menuitem" className={ITEM}>
      {children}
    </Link>
  );
}

function Chevron({ open }: { open: boolean }) {
  return (
    <svg
      aria-hidden
      viewBox="0 0 10 6"
      className={`h-[5px] w-[9px] shrink-0 fill-none stroke-fg-muted stroke-[1.5] transition-transform ${
        open ? "rotate-180" : ""
      }`}
    >
      <path d="M1 1l4 4 4-4" strokeLinecap="round" strokeLinejoin="round" />
    </svg>
  );
}

function initials(name: string): string {
  const parts = name.trim().split(/\s+/).filter(Boolean);
  if (parts.length === 0) return "?";
  if (parts.length === 1) return parts[0]!.slice(0, 1).toUpperCase();
  return (parts[0]!.slice(0, 1) + parts[parts.length - 1]!.slice(0, 1)).toUpperCase();
}
