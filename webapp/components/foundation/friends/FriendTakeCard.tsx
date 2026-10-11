"use client";

import { TakeCard } from "@/components/foundation/content/prompts/TakeCard";
import { TakePromptStrip } from "@/components/foundation/content/prompts/TakePromptStrip";
import { TakeResponse } from "@/components/foundation/content/prompts/TakeResponse";
import type { Post } from "@/lib/foundation/content/prompts/types";
import type { ActivityEvent } from "@/lib/foundation/friends/friends";

/**
 * A friend's answer to a locked prompt, drawn as the same take card the Huddle
 * uses: their take, then their picks. The prompt it answers is a quoted strip
 * inside the card, ahead of the take, and links to the prompt. The picks start
 * folded behind "View take", as other people's takes do in the Huddle, so a run
 * of long slates stays skimmable. `post` is null when the prompt is no longer
 * in the feed, and the card then shows the take alone.
 */
export function FriendTakeCard({ event, post }: { event: ActivityEvent; post: Post | null }) {
  const points = event.points;
  const caption = event.postCaption?.trim() || "a prompt";
  return (
    <div>
      <TakeCard
        comment={{
          id: event.commentId ?? `${event.actorId}-${event.postId}`,
          author: event.displayName,
          authorAvatarUrl: event.avatarUrl,
          authorUsername: event.username,
          body: event.takeBody ?? "",
          createdAt: event.occurredAt,
          isViewer: false,
          postedWithPick: true,
          replies: [],
        }}
        replyCount={event.replyCount}
        context={<TakePromptStrip postId={event.postId || null} caption={caption} />}
        collapsedByDefault
        // A friend who answered without posting a take has no thread of their own; the icon opens the prompt's discussion.
        commentHref={event.postId ? (event.commentId ? `/prompts/${event.postId}/takes/${event.commentId}` : `/prompts/${event.postId}`) : undefined}
        footer={
          points !== null && points > 0 ? (
            <span className={`grade-scoremark grade-scoremark--standings grade-scoremark--elite`}>+{points}</span>
          ) : undefined
        }
      >
        {post && event.response ? <TakeResponse post={post} response={event.response} isViewer={false} /> : null}
      </TakeCard>
    </div>
  );
}
