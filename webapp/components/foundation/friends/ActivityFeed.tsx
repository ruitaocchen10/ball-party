import Link from "next/link";

import { AuthorAvatar } from "@/components/foundation/content/prompts/AuthorIdentity";
import { ButtonLink } from "@/components/foundation/ui-kit/Button";
import { EmptyState } from "@/components/foundation/ui-kit/EmptyState";
import { FriendTakeCard } from "@/components/foundation/friends/FriendTakeCard";
import { GameMomentCard } from "@/components/foundation/friends/GameMomentCard";
import { groupActivity, timeAgo, type ActivityEvent } from "@/lib/foundation/friends/friends";
import type { Post } from "@/lib/foundation/content/prompts/types";

const LINK = "focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-fg";

/**
 * What friends have been doing over the last 30 days, as a feed of cards:
 * a friend's answer to a locked prompt is the Huddle's take card (their take,
 * then their picks), and a multiplayer win or a new solo best is a lighter
 * game card. While a prompt is still open the feed only says a friend answered;
 * the server leaves the choice out until the lock.
 *
 * Paging is by link: `olderHref` is the same page asking for events before the
 * last one shown, so the prompt data each take card needs is loaded with it.
 */
export function ActivityFeed({
  events,
  posts,
  hasFriends,
  olderHref,
}: {
  events: ActivityEvent[];
  /** The prompts the take cards draw their picks from, by id. */
  posts: Map<string, Post>;
  hasFriends: boolean;
  /** Null when the last page came back short: nothing older to ask for. */
  olderHref: string | null;
}) {
  if (events.length === 0) {
    return hasFriends ? (
      <EmptyState title="Nothing yet" className="mt-6">
        When your friends answer prompts, win games or set new high scores, it shows up here. Only the last 30 days are shown.
      </EmptyState>
    ) : (
      <EmptyState title="No friends yet" className="mt-6">
        Add friends to see their answers and wins here.{" "}
        <Link href="/profile?tab=friends" className={`text-fg underline underline-offset-2 ${LINK}`}>
          Find friends
        </Link>
      </EmptyState>
    );
  }

  return (
    <div className="pt-4">
      <ol className="flex flex-col gap-4">
        {groupActivity(events).map((item) => {
          const { event } = item;
          return (
            <li key={`${event.type}-${event.actorId}-${event.postId ?? event.matchId ?? event.game}-${event.mode ?? ""}-${event.occurredAt}`}>
              {event.type === "take" ? (
                <FriendTakeCard event={event} post={(event.postId && posts.get(event.postId)) || null} />
              ) : event.type === "pick_made" ? (
                <OpenPick event={event} />
              ) : (
                <GameMomentCard item={item} />
              )}
            </li>
          );
        })}
      </ol>
      {olderHref ? (
        <div className="mt-6 flex justify-center">
          <ButtonLink href={olderHref} variant="ghost" fullWidth={false}>
            Older
          </ButtonLink>
        </div>
      ) : (
        <p className="mt-6 text-center type-label text-fg-muted">That&apos;s the last 30 days.</p>
      )}
    </div>
  );
}

/** A friend who answered a prompt that hasn't locked: the fact, never the answer. */
function OpenPick({ event }: { event: ActivityEvent }) {
  const caption = event.postCaption?.trim() || "a prompt";
  return (
    <div className="flex items-center gap-3 px-1">
      <AuthorAvatar name={event.displayName} avatarUrl={event.avatarUrl} className="h-7 w-7" />
      <p className="min-w-0 flex-1 text-[15px] leading-6 text-fg-muted">
        <span className="font-semibold text-fg">{event.displayName}</span> answered{" "}
        {event.postId ? (
          <Link href={`/prompts/${event.postId}`} className={`underline underline-offset-2 hover:text-fg ${LINK}`}>
            {caption}
          </Link>
        ) : (
          caption
        )}
        . Their picks show when it locks.
      </p>
      <span className="shrink-0 font-mono text-[10px] tracking-[0.04em] text-fg-muted">{timeAgo(event.occurredAt).toUpperCase()}</span>
    </div>
  );
}
