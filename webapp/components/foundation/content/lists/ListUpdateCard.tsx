import Link from "next/link";
import type { ReactNode } from "react";

import { AuthorAvatar } from "@/components/foundation/content/prompts/AuthorIdentity";
import { Badge } from "@/components/foundation/ui-kit/Badge";
import { Card } from "@/components/foundation/ui-kit/Card";
import { timeAgo } from "@/lib/foundation/friends/friends";
import { biggestMoves, listPath, placeChange } from "@/lib/foundation/lists/lists";
import type { ListPlayer, ListUpdate } from "@/lib/foundation/lists/types";
import { ListItemFace, PlaceChange } from "./ListRows";

/**
 * A friend's published edit, as the feed and its own page show it: who, the
 * note, and the biggest moves against the list it replaced (not the whole
 * list). A first version has nothing to compare, so it shows the top of the
 * list. `children` is where the reply thread goes on the card's own page.
 */
export function ListUpdateCard({
  update,
  players,
  viewerId,
  children,
  full = false,
}: {
  update: ListUpdate;
  players: Record<string, ListPlayer>;
  viewerId: string;
  children?: ReactNode;
  /** On the card's own page, show the whole list instead of the biggest moves. */
  full?: boolean;
}) {
  const isYou = update.authorId === viewerId;
  const moves = biggestMoves(update.previousItems, update.items, 4);
  const shown = full
    ? update.items.map((item, index) => ({ item, place: index + 1 }))
    : moves.length
      ? moves
      : update.items.slice(0, 3).map((item, index) => ({ item, place: index + 1 }));
  const hidden = update.items.length - shown.length;

  return (
    <article>
      <Card>
        <div className="flex items-center gap-3 px-3 pt-3">
          <AuthorAvatar name={update.displayName} avatarUrl={update.avatarUrl} />
          <div className="min-w-0 flex-1 leading-tight">
            <p className="text-[15px] text-panel-soft">
              {update.username ? (
                <Link href={isYou ? "/profile?tab=lists" : `/u/${encodeURIComponent(update.username)}?tab=lists`} className="font-semibold text-panel-fg hover:underline">
                  {isYou ? "You" : update.displayName}
                </Link>
              ) : (
                <span className="font-semibold text-panel-fg">{update.displayName}</span>
              )}{" "}
              updated {isYou ? "your" : "their"} {update.label.toLowerCase()}
            </p>
            <p className="mt-1 type-label-xs text-panel-muted">{timeAgo(update.savedAt)} · Version {update.versionNo}</p>
          </div>
          <Badge tone="outline" size="xs">Friends only</Badge>
        </div>
        {update.note ? <p className="px-3 pt-3 text-[15px] leading-6 text-panel-fg">&ldquo;{update.note}&rdquo;</p> : null}
        <ol className="mt-3 divide-y divide-panel-line border-t border-panel-line">
          {shown.map(({ item, place }) => (
            <li key={item} className="grid grid-cols-[2rem_minmax(0,1fr)_auto] items-center gap-3 px-3 py-2">
              <span className="text-center font-slab text-2xl leading-none text-panel-fg tabular-nums">{place}</span>
              <ListItemFace item={item} itemKind={update.itemKind} players={players} />
              {update.previousItems ? <PlaceChange change={placeChange(update.previousItems, update.items, place - 1)} /> : <span />}
            </li>
          ))}
        </ol>
        {!full ? (
          <div className="flex items-center justify-between border-t border-panel-line px-3 py-3">
            <span className="type-label text-panel-muted">{hidden > 0 ? `+ ${hidden} more in the list` : " "}</span>
            <Link href={`/lists/updates/${update.postId}`} className="type-label text-panel-fg underline underline-offset-2">
              Open and reply
            </Link>
          </div>
        ) : (
          <div className="border-t border-panel-line px-3 py-3">
            <Link href={listPath(update.kind, isYou ? null : update.username)} className="type-label text-panel-muted underline underline-offset-2 hover:text-panel-fg">
              See the whole history
            </Link>
          </div>
        )}
      </Card>
      {children}
    </article>
  );
}
