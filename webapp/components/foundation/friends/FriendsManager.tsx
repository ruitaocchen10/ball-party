"use client";

import Link from "next/link";
import { useState } from "react";

import { AuthorAvatar } from "@/components/foundation/content/prompts/AuthorIdentity";
import { InviteLinkCard } from "@/components/foundation/friends/InviteLinkCard";
import { PlayerSearch } from "@/components/foundation/friends/PlayerSearch";
import { ConfirmAction } from "@/components/foundation/friends/ConfirmAction";
import { Badge } from "@/components/foundation/ui-kit/Badge";
import { Button } from "@/components/foundation/ui-kit/Button";
import { EmptyState } from "@/components/foundation/ui-kit/EmptyState";
import {
  friendErrorMessage,
  friendsDataFromRows,
  type FriendsData,
  type PlayerSummary,
} from "@/lib/foundation/friends/friends";
import { createClient } from "@/lib/supabase/client";

export type { FriendsData, PlayerSummary };

type Action = "accept" | "decline" | "cancel" | "remove" | "block" | "unblock";

const ACTION_RPC = {
  accept: "accept_friend_request",
  decline: "decline_friend_request",
  cancel: "cancel_friend_request",
  remove: "remove_friend",
  block: "block_user",
  unblock: "unblock_user",
} as const;

/**
 * Friends, requests, blocks, search and the invite link. The server rules live
 * in the RPCs; this just calls them and re-reads the three lists afterwards, so
 * the screen always shows what the database says rather than a local guess.
 */
export function FriendsManager({ initial, inviteCode }: { initial: FriendsData; inviteCode: string | null }) {
  const [data, setData] = useState(initial);
  const [busyId, setBusyId] = useState<string | null>(null);
  const [error, setError] = useState<string | null>(null);

  async function reload() {
    const supabase = createClient();
    const [friends, requests, blocked] = await Promise.all([
      supabase.rpc("list_friends"),
      supabase.rpc("list_friend_requests"),
      supabase.rpc("list_blocked_users"),
    ]);
    if (friends.error || requests.error || blocked.error) return;
    setData(friendsDataFromRows(friends.data ?? [], requests.data ?? [], blocked.data ?? []));
  }

  async function act(action: Action, player: PlayerSummary) {
    setBusyId(player.profileId);
    setError(null);
    const { error: rpcError } = await createClient().rpc(ACTION_RPC[action], { p_user_id: player.profileId });
    setBusyId(null);
    if (rpcError) {
      setError(friendErrorMessage(rpcError.message));
      return;
    }
    await reload();
  }

  const requestCount = data.incoming.length;

  return (
    <div className="flex flex-col gap-9 pt-6">
      {error ? <p role="alert" className="text-sm text-hidden-text">{error}</p> : null}

      <section aria-labelledby="add-friends-heading">
        <SectionHeading id="add-friends-heading">Add friends</SectionHeading>
        <div className="mt-3 grid gap-4">
          <PlayerSearch onChanged={reload} />
          {inviteCode ? <InviteLinkCard code={inviteCode} /> : null}
        </div>
      </section>

      {data.incoming.length > 0 || data.outgoing.length > 0 ? (
        <section aria-labelledby="requests-heading">
          <SectionHeading id="requests-heading">
            Requests{requestCount > 0 ? <Badge size="xs" className="ml-2">{requestCount} new</Badge> : null}
          </SectionHeading>
          <ul className="mt-3 border-t border-line">
            {data.incoming.map((player) => (
              <PlayerRow key={player.profileId} player={player} note="Wants to be friends">
                <Button size="sm" fullWidth={false} disabled={busyId !== null} aria-label={`Accept request from ${player.displayName}`} onClick={() => act("accept", player)}>
                  Accept
                </Button>
                <Button variant="text" size="sm" fullWidth={false} disabled={busyId !== null} aria-label={`Decline request from ${player.displayName}`} onClick={() => act("decline", player)}>
                  Decline
                </Button>
              </PlayerRow>
            ))}
            {data.outgoing.map((player) => (
              <PlayerRow key={player.profileId} player={player} note="Request sent">
                <Button variant="text" size="sm" fullWidth={false} disabled={busyId !== null} aria-label={`Cancel request to ${player.displayName}`} onClick={() => act("cancel", player)}>
                  Cancel
                </Button>
              </PlayerRow>
            ))}
          </ul>
        </section>
      ) : null}

      <section aria-labelledby="friends-list-heading">
        <SectionHeading id="friends-list-heading">
          Friends{data.friends.length > 0 ? ` · ${data.friends.length}` : ""}
        </SectionHeading>
        {data.friends.length === 0 ? (
          <EmptyState title="No friends yet" className="mt-3">
            Search for a username or share your invite link. Friends show up here once they accept.
          </EmptyState>
        ) : (
          <ul className="mt-3 border-t border-line">
            {data.friends.map((player) => (
              <PlayerRow key={player.profileId} player={player}>
                <ConfirmAction
                  label="Remove"
                  confirmLabel="Remove friend"
                  ariaLabel={`Remove ${player.displayName}`}
                  disabled={busyId !== null}
                  onConfirm={() => act("remove", player)}
                />
                <ConfirmAction
                  label="Block"
                  confirmLabel="Block"
                  ariaLabel={`Block ${player.displayName}`}
                  disabled={busyId !== null}
                  onConfirm={() => act("block", player)}
                />
              </PlayerRow>
            ))}
          </ul>
        )}
      </section>

      {data.blocked.length > 0 ? (
        <section aria-labelledby="blocked-heading">
          <SectionHeading id="blocked-heading">Blocked · {data.blocked.length}</SectionHeading>
          <p className="mt-2 text-sm leading-6 text-fg-muted">Blocked players can&apos;t find you or send you requests.</p>
          <ul className="mt-3 border-t border-line">
            {data.blocked.map((player) => (
              <PlayerRow key={player.profileId} player={player} link={false}>
                <Button variant="ghost" size="sm" fullWidth={false} disabled={busyId !== null} aria-label={`Unblock ${player.displayName}`} onClick={() => act("unblock", player)}>
                  Unblock
                </Button>
              </PlayerRow>
            ))}
          </ul>
        </section>
      ) : null}
    </div>
  );
}

export function SectionHeading({ id, children }: { id: string; children: React.ReactNode }) {
  return <h2 id={id} className="type-label font-bold text-fg-muted">{children}</h2>;
}

/** One person in a list: avatar, name, @username, and whatever actions the list offers. */
export function PlayerRow({
  player,
  note,
  link = true,
  children,
}: {
  player: PlayerSummary;
  note?: string;
  link?: boolean;
  children?: React.ReactNode;
}) {
  const identity = (
    <>
      <span className="block truncate font-medium">{player.displayName}</span>
      <span className="block truncate type-label-xs text-fg-muted">
        {player.username ? `@${player.username}` : null}
        {player.username && note ? " · " : null}
        {note}
      </span>
    </>
  );

  return (
    <li className="flex flex-wrap items-center gap-3 border-b border-line py-3">
      <AuthorAvatar name={player.displayName} avatarUrl={player.avatarUrl} className="h-9 w-9" />
      {link && player.username ? (
        <Link
          href={`/u/${player.username}`}
          className="min-w-0 flex-1 hover:text-fg-muted focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-fg"
        >
          {identity}
        </Link>
      ) : (
        <span className="min-w-0 flex-1">{identity}</span>
      )}
      {children ? <div className="flex items-center gap-2">{children}</div> : null}
    </li>
  );
}
