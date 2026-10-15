"use client";

import Link from "next/link";
import { useContext } from "react";
import { useRouter } from "next/navigation";

import { SearchQueryContext } from "@/components/home/search-context";
import { PostCardC } from "@/components/foundation/content/prompts/PromptPostUI";
import { GameMomentCard } from "@/components/foundation/friends/GameMomentCard";
import { EmptyState } from "@/components/foundation/ui-kit/EmptyState";
import { ButtonLink } from "@/components/foundation/ui-kit/Button";
import { matchesSearchQuery } from "@/lib/foundation/content/prompts/logic";
import type { MatchupGameContext, Post } from "@/lib/foundation/content/prompts/types";
import { ListUpdateCard } from "@/components/foundation/content/lists/ListUpdateCard";
import { buildHomeFeed, type ActivityEvent, type FriendAnswerer, type HomeFilter } from "@/lib/foundation/friends/friends";
import { mergeByTime } from "@/lib/foundation/lists/lists";
import type { ListPlayer, ListUpdate } from "@/lib/foundation/lists/types";

/**
 * Home's single feed: prompt cards and friends' game moments interleaved by
 * time, narrowed by the pill the viewer picked. `posts` is always the full,
 * unfiltered prompt list; the search query narrows it live as the viewer types.
 */
export function HuddleFeed({
  posts,
  canAnswer,
  gameContexts,
  filter,
  answerers,
  moments,
  before,
  pageFull,
  hasFriends,
  listUpdates,
  listPlayers,
  viewerId,
  listUpdatesFull,
}: {
  posts: Post[];
  canAnswer: boolean;
  gameContexts: MatchupGameContext[];
  filter: HomeFilter;
  answerers: Record<string, FriendAnswerer[]>;
  moments: ActivityEvent[];
  before: string | null;
  /** The last page of game moments came back full, so there may be older ones. */
  pageFull: boolean;
  hasFriends: boolean;
  /** Published list edits by you and your friends, newest first. */
  listUpdates: ListUpdate[];
  listPlayers: Record<string, ListPlayer>;
  viewerId: string | null;
  /** The last page of list updates came back full, so there may be older ones. */
  listUpdatesFull: boolean;
}) {
  const router = useRouter();
  const search = useContext(SearchQueryContext);
  const visiblePosts = search ? posts.filter((post) => matchesSearchQuery(post, search.query)) : posts;
  const built = buildHomeFeed({ posts: visiblePosts, answerers, moments: search?.query ? [] : moments, filter, before, pageFull });
  const updateEntries = viewerId && !search?.query ? listUpdates.map((update) => ({ kind: "list" as const, at: update.savedAt, update })) : [];
  const items = mergeByTime(built.items, updateEntries, { before, floor: built.olderBefore });
  const olderBefore = filter === "lists" ? (listUpdatesFull && listUpdates.length ? listUpdates[listUpdates.length - 1].savedAt : null) : built.olderBefore;

  return (
    <section aria-label="Huddle">
      {items.length === 0 ? (
        filter === "lists" ? (
          <EmptyState title="No list updates yet" className="mt-5">
            When you or your friends share a change to a list, it shows up here.{" "}
            <Link href="/lists" className="text-fg underline underline-offset-2">Build your lists</Link>
          </EmptyState>
        ) : filter === "friends" && !hasFriends ? (
          <EmptyState title="No friends yet" className="mt-5">
            Add friends to see which prompts they answer and their wins here.{" "}
            <Link href="/friends" className="text-fg underline underline-offset-2">Find friends</Link>
          </EmptyState>
        ) : filter === "friends" ? (
          <EmptyState title="Nothing yet" className="mt-5">
            When your friends answer prompts, win games or set new high scores, it shows up here. Only the last 30 days are shown.
          </EmptyState>
        ) : (
          <EmptyState title="The huddle is quiet" className="mt-5">New weekly picks will show up here.</EmptyState>
        )
      ) : (
        <div className="mt-5 w-full pb-16">
          <ol className="flex flex-col gap-5">
            {items.map((entry) => (
              <li key={entry.kind === "prompt" ? `prompt-${entry.post.id}` : entry.kind === "list" ? `list-${entry.update.postId}` : `${entry.item.event.type}-${entry.item.event.actorId}-${entry.item.event.matchId ?? entry.item.event.game}-${entry.item.event.mode ?? ""}-${entry.item.event.occurredAt}`}>
                {entry.kind === "list" ? (
                  <ListUpdateCard update={entry.update} players={listPlayers} viewerId={viewerId!} />
                ) : entry.kind === "prompt" ? (
                  <PostCardC post={entry.post} viewerCanAnswer={canAnswer} onOpenAnswer={() => router.push(`/prompts/${entry.post.id}`)} gameContexts={gameContexts} friendsAnswered={entry.answerers} />
                ) : (
                  <GameMomentCard item={entry.item} />
                )}
              </li>
            ))}
          </ol>
          {olderBefore ? (
            <div className="mt-6 flex justify-center">
              <ButtonLink href={`/?filter=${filter}&before=${encodeURIComponent(olderBefore)}`} variant="ghost" fullWidth={false}>
                Older
              </ButtonLink>
            </div>
          ) : null}
        </div>
      )}
    </section>
  );
}
