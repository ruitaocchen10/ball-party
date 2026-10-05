import { House } from "lucide-react";
import Link from "next/link";

import { AccountMenu } from "@/components/foundation/ui-kit/AccountMenu";
import { InviteSuite } from "@/components/platform/lobbies/InviteSuite";
import { Button } from "@/components/foundation/ui-kit/Button";
import { closeLobby, leaveLobby } from "@/lib/platform/lobbies/actions";

const FOCUS =
  "focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-panel";

/**
 * The lobby's own chrome — everything the persistent app rail would
 * otherwise cover, shrunk to a single row.
 *
 * A room is where the party actually is, not a page you browse from: once
 * you're in one, "Home", "Party" and "Solo" stop being places you'd go, and a
 * whole rail reserved for them is dead weight beside people waiting to play.
 * `app/lobby/[code]/page.tsx` mounts this instead of `<Sidebar>` for exactly
 * that reason — the same call a live match screen already makes (see
 * `Sidebar`'s own docstring on `data-sidebar-rail`), extended one screen
 * earlier. Leave/close move up here too, off the stack of ghost buttons the
 * bottom of the page used to end on, so they read as room controls rather
 * than settings.
 *
 * The invite suite (see InviteSuite) takes the middle once a real room
 * exists — the code used to sit in its own header below this strip, but an
 * invite is the thing you reach for most while the room is still filling up,
 * so it earned the always-on-screen spot instead of scrolling past with the
 * roster. `flex-wrap` plus the `order-*` swap below is what lets it drop to
 * a full-width row under the icon/actions on a narrow phone rather than
 * squeezing three groups into one line.
 */
export function LobbyTopStrip({
  lobbyId = null,
  code,
  isHost = false,
  displayName,
  email = null,
  avatarUrl = null,
}: {
  /** Absent before the room is known — the "no room yet" and "signed out"
   * states this same header renders for AutoJoinRoom/InviteAccountGate. */
  lobbyId?: string | null;
  code: string;
  isHost?: boolean;
  displayName?: string | null;
  email?: string | null;
  avatarUrl?: string | null;
}) {
  return (
    <header className="flex flex-wrap items-center justify-between gap-3 py-3">
      <Link
        href="/"
        aria-label="Home"
        className={`order-1 flex h-9 w-9 items-center justify-center bg-surface-raised text-fg ring-1 ring-line ring-inset transition-colors hover:text-fg-muted ${FOCUS}`}
      >
        <House className="h-[18px] w-[18px]" strokeWidth={1.5} />
      </Link>

      {lobbyId ? (
        <div className="order-3 basis-full sm:order-2 sm:basis-auto sm:mx-auto">
          <InviteSuite code={code} />
        </div>
      ) : null}

      <div className="order-2 flex items-center gap-2 sm:order-3">
        {lobbyId ? (
          <form action={leaveLobby}>
            <input type="hidden" name="lobby_id" value={lobbyId} />
            <Button type="submit" variant="ghost" fullWidth={false} className="min-h-9 px-3 text-[10px]">
              Leave room
            </Button>
          </form>
        ) : null}

        {lobbyId && isHost ? (
          <form action={closeLobby}>
            <input type="hidden" name="lobby_id" value={lobbyId} />
            <input type="hidden" name="code" value={code} />
            {/* Destructive, so it stays visually subordinate — red doubles as
                the danger colour here, same as the buttons this replaced. */}
            <Button
              type="submit"
              variant="ghost"
              fullWidth={false}
              className="min-h-9 px-3 text-[10px] text-hidden-text ring-hidden/40 hover:bg-hidden/10"
            >
              Close room
            </Button>
          </form>
        ) : null}

        {displayName ? (
          <AccountMenu displayName={displayName} email={email} avatarUrl={avatarUrl} compact />
        ) : (
          <Link
            href="/login"
            className={`type-label text-fg-muted transition-colors hover:text-fg ${FOCUS}`}
          >
            Sign in
          </Link>
        )}
      </div>
    </header>
  );
}
