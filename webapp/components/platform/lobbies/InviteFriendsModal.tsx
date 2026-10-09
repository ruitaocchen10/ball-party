"use client";

import Link from "next/link";
import { useEffect, useState } from "react";

import { AuthorAvatar } from "@/components/foundation/content/prompts/AuthorIdentity";
import { Badge } from "@/components/foundation/ui-kit/Badge";
import { Button } from "@/components/foundation/ui-kit/Button";
import { EmptyState } from "@/components/foundation/ui-kit/EmptyState";
import { Modal, ModalTitle } from "@/components/foundation/ui-kit/Modal";
import {
  INVITE_RESULT_COPY,
  inviteErrorMessage,
  isInviteSettled,
  parseInviteResult,
  type InviteResult,
} from "@/lib/platform/lobbies/invites";
import { createClient } from "@/lib/supabase/client";

type Friend = { profileId: string; username: string; displayName: string; avatarUrl: string | null };

/** Per friend: not asked yet, in flight, answered by the server, or failed to ask. */
type Attempt = { kind: "sending" } | { kind: "result"; result: InviteResult } | { kind: "error"; message: string };

/**
 * The friend picker behind "Invite friends" in a room. Friends are read when
 * the dialog opens (not with the page), so a friendship accepted a moment ago
 * is already in the list, and the lobby page pays nothing for it until used.
 * Every rule (who can be invited, a full room, a duplicate invite) is the
 * server's: this only shows the answer `invite_friend_to_room` gives per friend.
 */
export function InviteFriendsModal({ lobbyId, onClose }: { lobbyId: string; onClose: () => void }) {
  const [friends, setFriends] = useState<Friend[] | null>(null);
  const [loadError, setLoadError] = useState<string | null>(null);
  const [attempts, setAttempts] = useState<Record<string, Attempt>>({});

  useEffect(() => {
    let active = true;
    void createClient()
      .rpc("list_friends")
      .then(({ data, error }) => {
        if (!active) return;
        if (error) {
          setLoadError(inviteErrorMessage(error.message));
          return;
        }
        setFriends(
          (data ?? []).map((row) => ({
            profileId: row.profile_id,
            username: row.username,
            displayName: row.display_name,
            avatarUrl: row.avatar_url,
          })),
        );
      });
    return () => {
      active = false;
    };
  }, []);

  async function invite(friendId: string) {
    setAttempts((prev) => ({ ...prev, [friendId]: { kind: "sending" } }));
    const { data, error } = await createClient().rpc("invite_friend_to_room", {
      p_lobby_id: lobbyId,
      p_friend_id: friendId,
    });
    setAttempts((prev) => ({
      ...prev,
      [friendId]: error
        ? { kind: "error", message: inviteErrorMessage(error.message) }
        : { kind: "result", result: parseInviteResult(data) },
    }));
  }

  return (
    <Modal onClose={onClose} closeLabel="Close invite friends">
      <ModalTitle className="font-slab text-3xl uppercase">Invite friends</ModalTitle>
      <p className="mt-2 text-sm leading-6 text-fg-muted">
        They&apos;ll get the invite on their Party page and can join straight from there.
      </p>

      <div className="mt-4">
        {loadError ? (
          <p role="alert" className="text-sm text-hidden-text">{loadError}</p>
        ) : friends === null ? (
          <p role="status" className="text-sm text-fg-muted">Loading friends…</p>
        ) : friends.length === 0 ? (
          <EmptyState title="No friends yet">
            Add friends and you can invite them here.{" "}
            <Link href="/profile?tab=friends" className="text-fg underline underline-offset-2">Find friends</Link>
          </EmptyState>
        ) : (
          <ul className="border-t border-line">
            {friends.map((friend) => (
              <FriendRow key={friend.profileId} friend={friend} attempt={attempts[friend.profileId]} onInvite={invite} />
            ))}
          </ul>
        )}
      </div>
    </Modal>
  );
}

function FriendRow({
  friend,
  attempt,
  onInvite,
}: {
  friend: Friend;
  attempt: Attempt | undefined;
  onInvite: (friendId: string) => void;
}) {
  const settled = attempt?.kind === "result" && isInviteSettled(attempt.result);
  const sending = attempt?.kind === "sending";

  return (
    <li className="flex items-center gap-3 border-b border-line py-2.5">
      <AuthorAvatar name={friend.displayName} avatarUrl={friend.avatarUrl} className="h-8 w-8" />
      <span className="min-w-0 flex-1">
        <span className="block truncate font-medium">{friend.displayName}</span>
        <span className="block truncate type-label-xs text-fg-muted">@{friend.username}</span>
        {attempt?.kind === "error" ? (
          <span role="alert" className="block text-xs text-hidden-text">{attempt.message}</span>
        ) : null}
      </span>

      {attempt?.kind === "result" ? (
        <Badge tone={attempt.result === "invited" ? "success" : "muted"}>
          {INVITE_RESULT_COPY[attempt.result].label}
        </Badge>
      ) : null}
      {attempt?.kind === "result" ? <span className="sr-only">{INVITE_RESULT_COPY[attempt.result].detail}</span> : null}

      {!settled ? (
        <Button
          type="button"
          size="sm"
          fullWidth={false}
          disabled={sending}
          aria-label={`Invite ${friend.displayName}`}
          onClick={() => onInvite(friend.profileId)}
        >
          {sending ? "Inviting…" : attempt ? "Try again" : "Invite"}
        </Button>
      ) : null}
    </li>
  );
}
