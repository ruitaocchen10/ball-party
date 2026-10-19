"use client";

import { useState } from "react";

import { Button } from "@/components/foundation/ui-kit/Button";
import { Card } from "@/components/foundation/ui-kit/Card";
import { track } from "@/lib/foundation/analytics/client";
import { friendInvitePath } from "@/lib/foundation/friends/friends";

/**
 * A one-row bar below the Home filter pills that shares the player's friend
 * invite link. The page decides who sees it (a real account); it has no
 * dismiss, so it is always there for them. It is the light card, so it stands
 * out from the dark panels around it.
 */
export function InviteBar({ code }: { code: string }) {
  const [copied, setCopied] = useState(false);
  const [error, setError] = useState<string | null>(null);

  async function invite() {
    setError(null);
    const url = `${window.location.origin}${friendInvitePath(code)}`;
    if (typeof navigator.share === "function") {
      try {
        await navigator.share({ title: "Ball Party", text: "Add me on Ball Party.", url });
        track("invite_link_shared", { kind: "friend" });
      } catch (shareError) {
        // Closing the share sheet is not a failure.
        if (!(shareError instanceof DOMException && shareError.name === "AbortError")) {
          setError("Couldn't open sharing. Copy your link from Friends instead.");
        }
      }
      return;
    }
    try {
      await navigator.clipboard.writeText(url);
      track("invite_link_shared", { kind: "friend" });
      setCopied(true);
      setTimeout(() => setCopied(false), 2000);
    } catch {
      setError("Couldn't copy. Copy your link from Friends instead.");
    }
  }

  return (
    <Card tone="light" className="mt-5">
      <div className="flex items-center gap-3 py-3 pl-4 pr-2">
        <div className="min-w-0 flex-1">
          <p className="font-slab text-xl uppercase leading-none tracking-[0.04em]">Invite your friends</p>
          <p className="hidden text-sm text-surface/70 sm:block">Send your link to friends.</p>
        </div>
        <Button type="button" variant="dark" size="sm" fullWidth={false} onClick={invite}>
          {copied ? "Copied" : "Invite"}
        </Button>
      </div>
      <p role="status" className="px-4 pb-2 text-xs text-hidden-ink empty:hidden">{error}</p>
    </Card>
  );
}
