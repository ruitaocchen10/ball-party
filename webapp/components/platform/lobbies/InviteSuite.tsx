"use client";

import { useState } from "react";
import { Button } from "@/components/foundation/ui-kit/Button";
import { track } from "@/lib/foundation/analytics/client";
import { InviteFriendsModal } from "@/components/platform/lobbies/InviteFriendsModal";

/**
 * The room's one invite surface: invite a friend, or hand anyone a working
 * link. There is no code to read out; the link is the way in.
 * /lobby/[code] already handles a cold landing — InviteAccountGate and
 * AutoJoinRoom (see app/lobby/[code]/page.tsx) are exactly what a stranger
 * following this link hits — so there is nothing new to wire up
 * server-side, only a way to hand the link over. Lives in LobbyTopStrip's
 * own empty middle rather than the old below-strip header, so inviting is
 * always in reach instead of scrolled past once the roster fills the screen.
 *
 * `navigator.share` (the OS share sheet — Messages, Mail, AirDrop, whatever
 * the device offers) is preferred where it exists, since "text this to a
 * friend" is exactly what it is for. Everywhere else falls back to copying
 * the link to the clipboard.
 */
export function InviteSuite({ code, lobbyId }: { code: string; lobbyId: string }) {
  const [friendsOpen, setFriendsOpen] = useState(false);
  const [linkCopied, setLinkCopied] = useState(false);

  async function shareLink() {
    const url = `${window.location.origin}/lobby/${code}`;
    if (typeof navigator.share === "function") {
      try {
        await navigator.share({ title: "Join my Ball Party room", text: "Join my Ball Party room", url });
        track("invite_link_shared", { kind: "room" });
      } catch {
        // Cancelled share sheet — not an error worth surfacing.
      }
      return;
    }
    try {
      await navigator.clipboard.writeText(url);
      track("invite_link_shared", { kind: "room" });
      setLinkCopied(true);
      setTimeout(() => setLinkCopied(false), 1800);
    } catch {
      // Nothing to fall back to if the clipboard itself is blocked.
    }
  }

  return (
    <div className="flex items-center gap-2">
      <Button size="sm" fullWidth={false} type="button" onClick={() => setFriendsOpen(true)}>
        Invite friends
      </Button>
      <Button size="sm" variant="ghost" fullWidth={false} type="button" onClick={shareLink}>
        {linkCopied ? "Link copied" : "Share link"}
      </Button>

      {friendsOpen ? <InviteFriendsModal lobbyId={lobbyId} onClose={() => setFriendsOpen(false)} /> : null}
    </div>
  );
}
