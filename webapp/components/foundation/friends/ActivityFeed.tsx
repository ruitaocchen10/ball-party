"use client";

import Link from "next/link";
import { useState } from "react";

import { AuthorAvatar } from "@/components/foundation/content/prompts/AuthorIdentity";
import { Button } from "@/components/foundation/ui-kit/Button";
import { EmptyState } from "@/components/foundation/ui-kit/EmptyState";
import {
  ACTIVITY_PAGE_SIZE,
  activityEvents,
  friendErrorMessage,
  ordinalPlace,
  timeAgo,
  type ActivityEvent,
} from "@/lib/foundation/friends/friends";
import { MATCH_GAME_NAMES } from "@/lib/platform/orchestration/catalog";
import { createClient } from "@/lib/supabase/client";

/**
 * What friends have been doing over the last 30 days. Picks show that a friend
 * answered, never what they chose; the server leaves the choice out entirely.
 * "Load more" pages with the oldest time seen so far.
 */
export function ActivityFeed({ initial, hasFriends }: { initial: ActivityEvent[]; hasFriends: boolean }) {
  const [events, setEvents] = useState(initial);
  const [done, setDone] = useState(initial.length < ACTIVITY_PAGE_SIZE);
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<string | null>(null);

  async function loadMore() {
    const oldest = events[events.length - 1]?.occurredAt;
    if (!oldest) return;
    setBusy(true);
    setError(null);
    const { data, error: rpcError } = await createClient().rpc("friend_activity", {
      p_limit: ACTIVITY_PAGE_SIZE,
      p_before: oldest,
    });
    setBusy(false);
    if (rpcError) {
      setError(friendErrorMessage(rpcError.message));
      return;
    }
    const rows = data ?? [];
    setEvents((prev) => [...prev, ...activityEvents(rows)]);
    if (rows.length < ACTIVITY_PAGE_SIZE) setDone(true);
  }

  if (events.length === 0) {
    return hasFriends ? (
      <EmptyState title="Nothing yet" className="mt-6">
        When your friends make picks or finish games, it shows up here. Only the last 30 days are shown.
      </EmptyState>
    ) : (
      <EmptyState title="No friends yet" className="mt-6">
        Add friends to see their picks and results here.{" "}
        <Link href="/profile?tab=friends" className="text-fg underline underline-offset-2 focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-panel">
          Find friends
        </Link>
      </EmptyState>
    );
  }

  return (
    <div className="pt-4">
      <ol className="border-t border-line">
        {events.map((event) => (
          <li key={`${event.type}-${event.actorId}-${event.postId ?? event.matchId}-${event.occurredAt}`} className="flex items-start gap-3 border-b border-line py-3">
            <AuthorAvatar name={event.displayName} avatarUrl={event.avatarUrl} className="h-9 w-9" />
            <div className="min-w-0 flex-1">
              <p className="text-[15px] leading-6">{describe(event)}</p>
              <p className="type-label-xs text-fg-muted">{timeAgo(event.occurredAt)}</p>
            </div>
          </li>
        ))}
      </ol>
      {error ? <p role="alert" className="mt-3 text-sm text-hidden-text">{error}</p> : null}
      {done ? (
        <p className="mt-4 text-center type-label text-fg-muted">That&apos;s the last 30 days.</p>
      ) : (
        <div className="mt-4 flex justify-center">
          <Button type="button" variant="ghost" fullWidth={false} disabled={busy} onClick={loadMore}>
            {busy ? "Loading…" : "Load more"}
          </Button>
        </div>
      )}
    </div>
  );
}

function Actor({ event }: { event: ActivityEvent }) {
  return event.username ? (
    <Link href={`/u/${event.username}`} className="font-semibold hover:text-fg-muted focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-panel">
      {event.displayName}
    </Link>
  ) : (
    <span className="font-semibold">{event.displayName}</span>
  );
}

function Prompt({ event }: { event: ActivityEvent }) {
  const caption = event.postCaption?.trim() || "a prompt";
  return event.postId ? (
    <Link href={`/prompts/${event.postId}`} className="underline underline-offset-2 hover:text-fg-muted focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-panel">
      {caption}
    </Link>
  ) : (
    <span>{caption}</span>
  );
}

function describe(event: ActivityEvent) {
  switch (event.type) {
    case "pick_made":
      return (
        <>
          <Actor event={event} /> made a pick on <Prompt event={event} />
        </>
      );
    case "pick_result": {
      const points = event.points ?? 0;
      return (
        <>
          <Actor event={event} /> scored {points.toLocaleString("en-US")} {points === 1 ? "point" : "points"} on <Prompt event={event} />
        </>
      );
    }
    case "match_result": {
      const game = event.game && event.game in MATCH_GAME_NAMES ? MATCH_GAME_NAMES[event.game as keyof typeof MATCH_GAME_NAMES] : "a game";
      const place = event.placement !== null ? ` finished ${ordinalPlace(event.placement)} in ` : " played ";
      const score = event.rawScore !== null ? ` · score ${event.rawScore}` : "";
      return (
        <>
          <Actor event={event} />
          {place}
          {game}
          {score}
        </>
      );
    }
  }
}
