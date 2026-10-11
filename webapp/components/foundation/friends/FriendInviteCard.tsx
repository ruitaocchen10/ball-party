"use client";

import Link from "next/link";
import { useState } from "react";

import { AuthorAvatar } from "@/components/foundation/content/prompts/AuthorIdentity";
import { Button, ButtonLink } from "@/components/foundation/ui-kit/Button";
import {
  SEND_RESULT_COPY,
  friendErrorMessage,
  parseSendResult,
  type Relationship,
  type SendResult,
} from "@/lib/foundation/friends/friends";
import { createClient } from "@/lib/supabase/client";

export type InviteOwner = {
  username: string;
  displayName: string;
  avatarUrl: string | null;
  relationship: Relationship;
};

/**
 * The invite landing card: "X invited you". Opening the link does nothing by
 * itself; the visitor taps to send the request, which the owner still accepts.
 */
export function FriendInviteCard({ code, owner }: { code: string; owner: InviteOwner }) {
  const [result, setResult] = useState<SendResult | null>(
    owner.relationship === "friends" ? "already_friends" : owner.relationship === "outgoing" ? "already_requested" : null,
  );
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<string | null>(null);

  async function redeem() {
    setBusy(true);
    setError(null);
    const { data, error: rpcError } = await createClient().rpc("redeem_friend_code", { p_code: code });
    setBusy(false);
    if (rpcError) {
      setError(friendErrorMessage(rpcError.message));
      return;
    }
    setResult(parseSendResult(data));
  }

  return (
    <section className="rounded-card bg-surface-raised p-6 text-center shadow-well">
      <div className="flex justify-center">
        <AuthorAvatar name={owner.displayName} avatarUrl={owner.avatarUrl} className="h-16 w-16" />
      </div>
      <p className="mt-4 type-label text-fg-muted">Friend invite</p>
      <h1 className="mt-1 font-slab text-[34px] leading-none uppercase">{owner.displayName} invited you</h1>
      <p className="mt-1 type-label-xs text-fg-muted">@{owner.username}</p>

      <div className="mx-auto mt-6 flex max-w-xs flex-col gap-3">
        {result === null ? (
          <Button type="button" disabled={busy} onClick={redeem}>
            {busy ? "Sending…" : "Add friend"}
          </Button>
        ) : (
          <p role="status" className="text-sm text-fg">
            {SEND_RESULT_COPY[result]}
          </p>
        )}
        {error ? <p role="alert" className="text-sm text-hidden-text">{error}</p> : null}
        <ButtonLink href="/profile?tab=friends" variant="ghost">
          Go to friends
        </ButtonLink>
        <Link
          href={`/u/${owner.username}`}
          className="type-label text-fg-muted underline underline-offset-2 hover:text-fg focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-fg"
        >
          View profile
        </Link>
      </div>
    </section>
  );
}
