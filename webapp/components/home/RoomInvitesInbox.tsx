"use client";

import { useState } from "react";
import { useRouter } from "next/navigation";

import { AuthorAvatar } from "@/components/foundation/content/prompts/AuthorIdentity";
import { Button } from "@/components/foundation/ui-kit/Button";
import { inviteErrorMessage, inviteRoomSummary } from "@/lib/platform/lobbies/invites";
import { MATCH_GAME_NAMES, type MatchGame } from "@/lib/platform/orchestration/catalog";
import { createClient } from "@/lib/supabase/client";

export type RoomInvite = {
  inviteId: string;
  senderName: string;
  senderUsername: string;
  senderAvatarUrl: string | null;
  selectedGame: string | null;
  memberCount: number;
};

/**
 * Pending room invites from friends, on the Party page. Accepting joins the
 * room (the server runs the same `join_lobby` a code does, so a full or closed
 * room is refused there) and goes straight into it. Declining just clears the
 * row. Invites are pull-only: they appear when this page is loaded, with no push.
 */
export function RoomInvitesInbox({ invites: initial, hasRoom = false }: { invites: RoomInvite[]; hasRoom?: boolean }) {
  const router = useRouter();
  const [invites, setInvites] = useState(initial);
  const [busy, setBusy] = useState<{ id: string; action: "accept" | "decline" } | null>(null);
  const [errors, setErrors] = useState<Record<string, string>>({});

  if (invites.length === 0) return null;

  const drop = (id: string) => setInvites((prev) => prev.filter((invite) => invite.inviteId !== id));

  async function accept(id: string) {
    setBusy({ id, action: "accept" });
    setErrors((prev) => ({ ...prev, [id]: "" }));
    const { data, error } = await createClient().rpc("accept_room_invite", { p_invite_id: id });
    if (error || !data) {
      const message = error?.message ?? "";
      setBusy(null);
      // A dead invite (expired, room closed, unfriended) will never work: clear it.
      if (message === "invite_not_found") {
        setErrors((prev) => ({ ...prev, [id]: inviteErrorMessage(message) }));
        setTimeout(() => drop(id), 2500);
        return;
      }
      setErrors((prev) => ({ ...prev, [id]: inviteErrorMessage(message) }));
      return;
    }
    router.push(`/lobby/${data.code}`);
  }

  async function decline(id: string) {
    setBusy({ id, action: "decline" });
    const { error } = await createClient().rpc("decline_room_invite", { p_invite_id: id });
    setBusy(null);
    if (error) {
      setErrors((prev) => ({ ...prev, [id]: inviteErrorMessage(error.message) }));
      return;
    }
    drop(id);
  }

  return (
    <section aria-labelledby="room-invites-heading" className="pt-7">
      <h2 id="room-invites-heading" className="font-slab text-2xl leading-[1.02] uppercase sm:text-3xl">
        Room invites
      </h2>
      {hasRoom ? (
        <p className="mt-2 text-[15px] leading-[1.6] text-fg-muted">Heads up — joining an invite leaves the room you&apos;re in.</p>
      ) : null}

      <ul className="mt-4 border-t border-line">
        {invites.map((invite) => {
          const game =
            invite.selectedGame && invite.selectedGame in MATCH_GAME_NAMES
              ? MATCH_GAME_NAMES[invite.selectedGame as MatchGame]
              : null;
          const mine = busy?.id === invite.inviteId;
          return (
            <li key={invite.inviteId} className="flex flex-wrap items-center gap-3 border-b border-line py-3">
              <AuthorAvatar name={invite.senderName} avatarUrl={invite.senderAvatarUrl} className="h-9 w-9" />
              <span className="min-w-0 flex-1">
                <span className="block truncate font-medium">{invite.senderName} invited you</span>
                <span className="block type-label-xs text-fg-muted">
                  {inviteRoomSummary(game, invite.memberCount)}
                </span>
                {errors[invite.inviteId] ? (
                  <span role="alert" className="block text-xs text-hidden-text">{errors[invite.inviteId]}</span>
                ) : null}
              </span>
              <div className="flex items-center gap-2">
                <Button
                  type="button"
                  variant="text"
                  size="sm"
                  fullWidth={false}
                  disabled={busy !== null}
                  aria-label={`Decline invite from ${invite.senderName}`}
                  onClick={() => decline(invite.inviteId)}
                >
                  Decline
                </Button>
                <Button
                  type="button"
                  size="sm"
                  fullWidth={false}
                  disabled={busy !== null}
                  aria-label={`Join ${invite.senderName}'s room`}
                  onClick={() => accept(invite.inviteId)}
                >
                  {mine && busy.action === "accept" ? "Joining…" : "Join"}
                </Button>
              </div>
            </li>
          );
        })}
      </ul>
    </section>
  );
}
