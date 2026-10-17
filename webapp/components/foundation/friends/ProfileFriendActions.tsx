"use client";

import { useRouter } from "next/navigation";
import { useState } from "react";

import { ConfirmAction } from "@/components/foundation/friends/ConfirmAction";
import { ReportProfileButton } from "@/components/foundation/moderation/ReportButton";
import { Button } from "@/components/foundation/ui-kit/Button";
import { SEND_RESULT_COPY, friendErrorMessage, parseSendResult, type Relationship } from "@/lib/foundation/friends/friends";
import { createClient } from "@/lib/supabase/client";

/**
 * Friend actions in another player's profile header, by the viewer's
 * relationship to them. Every rule (who may ask whom, blocks) is the server's;
 * this only picks which buttons to offer and refreshes the page afterwards so
 * the profile re-reads what the viewer may now see.
 */
export function ProfileFriendActions({
  profileId,
  username,
  displayName,
  relationship,
}: {
  profileId: string;
  username: string;
  displayName: string;
  relationship: Relationship;
}) {
  const router = useRouter();
  const [busy, setBusy] = useState(false);
  const [message, setMessage] = useState<string | null>(null);

  async function run(call: () => PromiseLike<{ data: unknown; error: { message: string } | null }>, describe?: (data: unknown) => string) {
    setBusy(true);
    setMessage(null);
    const { data, error } = await call();
    setBusy(false);
    if (error) {
      setMessage(friendErrorMessage(error.message));
      return;
    }
    if (describe) setMessage(describe(data));
    router.refresh();
  }

  const supabase = createClient();
  const target = { p_user_id: profileId };

  let buttons: React.ReactNode = null;
  switch (relationship) {
    case "none":
      buttons = (
        <Button size="sm" fullWidth={false} disabled={busy} onClick={() => run(() => supabase.rpc("send_friend_request", { p_username: username }), (data) => SEND_RESULT_COPY[parseSendResult(data)])}>
          Add friend
        </Button>
      );
      break;
    case "incoming":
      buttons = (
        <>
          <Button size="sm" fullWidth={false} disabled={busy} onClick={() => run(() => supabase.rpc("accept_friend_request", target))}>
            Accept request
          </Button>
          <Button variant="text" size="sm" fullWidth={false} disabled={busy} onClick={() => run(() => supabase.rpc("decline_friend_request", target))}>
            Decline
          </Button>
        </>
      );
      break;
    case "outgoing":
      buttons = (
        <Button variant="ghost" size="sm" fullWidth={false} disabled={busy} onClick={() => run(() => supabase.rpc("cancel_friend_request", target))}>
          Cancel request
        </Button>
      );
      break;
    case "friends":
      buttons = (
        <ConfirmAction
          label="Remove friend"
          confirmLabel="Remove"
          ariaLabel={`Remove ${displayName} as a friend`}
          disabled={busy}
          onConfirm={() => run(() => supabase.rpc("remove_friend", target))}
        />
      );
      break;
    case "blocked":
      buttons = (
        <Button variant="ghost" size="sm" fullWidth={false} disabled={busy} onClick={() => run(() => supabase.rpc("unblock_user", target))}>
          Unblock
        </Button>
      );
      break;
    default:
      return null;
  }

  return (
    <div className="flex flex-col items-start gap-2 sm:items-end">
      <div className="flex items-center gap-2">
        {buttons}
        <ReportProfileButton profileId={profileId} displayName={displayName} />
      </div>
      {message ? <p role="status" className="text-xs text-fg-muted">{message}</p> : null}
    </div>
  );
}
