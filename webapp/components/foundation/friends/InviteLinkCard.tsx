"use client";

import { useState } from "react";

import { ConfirmAction } from "@/components/foundation/friends/ConfirmAction";
import { Button } from "@/components/foundation/ui-kit/Button";
import { Input } from "@/components/foundation/ui-kit/Input";
import { track } from "@/lib/foundation/analytics/client";
import { friendErrorMessage, friendInvitePath } from "@/lib/foundation/friends/friends";
import { createClient } from "@/lib/supabase/client";

/**
 * Your invite link. Anyone who opens it can ask to be your friend (you still
 * accept). Resetting swaps the code so links already shared stop working.
 */
export function InviteLinkCard({ code: initialCode }: { code: string }) {
  const [code, setCode] = useState(initialCode);
  const [copied, setCopied] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [resetting, setResetting] = useState(false);

  const link = `${typeof window === "undefined" ? "" : window.location.origin}${friendInvitePath(code)}`;

  async function copy() {
    try {
      await navigator.clipboard.writeText(link);
      track("invite_link_shared", { kind: "friend" });
      setCopied(true);
      setTimeout(() => setCopied(false), 2000);
    } catch {
      setError("Couldn't copy. Select the link and copy it by hand.");
    }
  }

  async function reset() {
    setResetting(true);
    setError(null);
    const { data, error: rpcError } = await createClient().rpc("reset_friend_code");
    setResetting(false);
    if (rpcError || !data) {
      setError(friendErrorMessage(rpcError?.message));
      return;
    }
    setCode(data);
    setCopied(false);
  }

  return (
    <div className="rounded-card bg-surface-raised p-4 shadow-well">
      <p className="type-label font-bold text-fg-muted">Your invite link</p>
      <p className="mt-1.5 text-sm leading-6 text-fg-muted">
        Share it anywhere. Anyone who opens it can ask to be your friend, and you decide whether to accept.
      </p>
      <div className="mt-3 flex flex-col gap-2 sm:flex-row">
        <Input variant="well" readOnly value={link} aria-label="Invite link" onFocus={(event) => event.currentTarget.select()} />
        <Button type="button" fullWidth={false} className="sm:min-w-28" onClick={copy}>
          {copied ? "Copied" : "Copy"}
        </Button>
      </div>
      <div className="mt-2 flex items-center justify-between gap-3">
        <p role="status" className="text-xs text-hidden-text">{error}</p>
        <ConfirmAction
          label="Reset link"
          confirmLabel={resetting ? "Resetting…" : "Reset, old links stop working"}
          ariaLabel="Reset invite link"
          disabled={resetting}
          onConfirm={reset}
        />
      </div>
    </div>
  );
}
