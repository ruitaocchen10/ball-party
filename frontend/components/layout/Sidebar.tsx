import Link from "next/link";

import { signOut } from "@/lib/auth/actions";
import { goToLobby } from "@/lib/lobbies/actions";

/**
 * The app's persistent navigation. On wider screens it is a fixed rail so the
 * room code is always within reach without competing with page content. Small
 * screens retain a compact bar: a rail would leave too little room to play.
 */
export function Sidebar({ displayName }: { displayName?: string | null }) {
  return (
    <>
      <header className="sticky top-0 z-10 border-b border-line bg-surface/92 backdrop-blur-sm lg:hidden">
        <div className="flex h-14 w-full items-center gap-3 px-4 sm:px-6">
          <Brand />
          <div className="flex-1" />
          <JoinRoom compact />
          <Account displayName={displayName} compact />
        </div>
      </header>

      <aside className="fixed inset-y-0 left-0 z-10 hidden w-64 flex-col border-r border-line bg-surface-raised/70 px-6 py-7 lg:flex">
        <Brand />

        <div className="mt-10 border-y border-line py-5">
          <p className="mb-3 font-mono text-[9px] tracking-[0.16em] text-fg-muted uppercase">
            Join a room
          </p>
          <JoinRoom />
        </div>

        <div className="flex-1" />
        <Account displayName={displayName} />
      </aside>
    </>
  );
}

function Brand() {
  return (
    <Link
      href="/"
      className="shrink-0 font-slab text-[17px] leading-none -skew-x-7 uppercase text-fg"
    >
      Ball Party
    </Link>
  );
}

function JoinRoom({ compact = false }: { compact?: boolean }) {
  return (
    <form action={goToLobby} className={compact ? "flex shrink-0 items-center gap-2" : "flex flex-col gap-2.5"}>
      <label htmlFor={compact ? "sidebar-code-mobile" : "sidebar-code"} className="sr-only">
        Room code
      </label>
      <input
        id={compact ? "sidebar-code-mobile" : "sidebar-code"}
        name="code"
        required
        maxLength={5}
        autoCapitalize="characters"
        autoComplete="off"
        spellCheck={false}
        placeholder="K7M2Q"
        aria-label="Room code"
        className={`rounded-[3px] border border-line bg-surface px-2.5 font-mono text-[13px] tracking-[0.18em] text-fg uppercase outline-none placeholder:text-fg-muted focus:border-panel ${
          compact ? "h-8 w-[82px] sm:w-[108px] sm:tracking-[0.24em]" : "h-10 w-full tracking-[0.24em]"
        }`}
      />
      <button
        type="submit"
        className={`shrink-0 cursor-pointer rounded-[3px] bg-panel font-mono text-[10px] font-bold tracking-[0.13em] text-panel-fg uppercase transition-colors hover:bg-[#fffdf7] ${
          compact ? "h-8 px-3" : "h-10 w-full"
        }`}
      >
        Join
      </button>
    </form>
  );
}

function Account({ displayName, compact = false }: { displayName?: string | null; compact?: boolean }) {
  if (displayName) {
    return (
      <div className={compact ? "flex shrink-0 items-center gap-2" : "border-t border-line pt-5"}>
        <div className="flex items-center gap-2.5">
          <span
            aria-hidden
            className="flex h-7 w-7 items-center justify-center rounded-[3px] bg-panel font-slab text-xs leading-none -skew-x-7 text-panel-fg shadow-card"
          >
            {initials(displayName)}
          </span>
          <span className="hidden min-w-0 truncate font-mono text-[10px] tracking-[0.11em] text-fg uppercase lg:block">
            {displayName}
          </span>
        </div>
        <form action={signOut} className={compact ? "" : "mt-3"}>
          <button
            type="submit"
            className="cursor-pointer font-mono text-[10px] tracking-[0.13em] text-fg-muted uppercase transition-colors hover:text-fg"
          >
            {compact ? "Out" : "Sign out"}
          </button>
        </form>
      </div>
    );
  }

  return (
    <div className={compact ? "flex shrink-0 items-center gap-3" : "flex flex-col gap-3 border-t border-line pt-5"}>
      <Link
        href="/login"
        className={`font-mono text-[10px] tracking-[0.13em] text-fg-muted uppercase transition-colors hover:text-fg ${
          compact ? "hidden sm:block" : ""
        }`}
      >
        Sign in
      </Link>
      <Link
        href="/signup"
        className={`flex items-center justify-center rounded-[3px] bg-panel font-mono text-[10px] font-bold tracking-[0.13em] text-panel-fg uppercase transition-colors hover:bg-[#fffdf7] ${
          compact ? "h-8 px-3.5" : "h-10"
        }`}
      >
        Sign up
      </Link>
    </div>
  );
}

function initials(name: string): string {
  const parts = name.trim().split(/\s+/).filter(Boolean);
  if (parts.length === 0) return "?";
  if (parts.length === 1) return parts[0]!.slice(0, 1).toUpperCase();
  return (parts[0]!.slice(0, 1) + parts[parts.length - 1]!.slice(0, 1)).toUpperCase();
}
