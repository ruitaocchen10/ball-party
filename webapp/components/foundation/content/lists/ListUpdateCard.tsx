import Link from "next/link";
import type { ReactNode } from "react";

import { TakeCard } from "@/components/foundation/content/prompts/TakeCard";
import { Badge } from "@/components/foundation/ui-kit/Badge";
import { listPath, placeChange } from "@/lib/foundation/lists/lists";
import type { ListPlayer, ListUpdate } from "@/lib/foundation/lists/types";
import { ListTile, listGridClass } from "./ListRows";

/**
 * A friend's published edit, drawn as a take card like every other post: who,
 * when, the note as the take, and under it the whole new list with how far
 * each item moved against the list it replaced (a first version has nothing
 * to compare, so no marks). `children` is where the reply thread goes on the
 * card's own page.
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
  /** On the card's own page: no link to itself, and the history link instead. */
  full?: boolean;
}) {
  const isYou = update.authorId === viewerId;
  const historyHref = listPath(update.kind, isYou ? null : update.username);

  return (
    <TakeCard
      comment={{
        id: update.postId,
        authorId: update.authorId,
        author: update.displayName,
        authorAvatarUrl: update.avatarUrl,
        authorUsername: update.username,
        body: update.note ?? "",
        createdAt: update.savedAt,
        isViewer: isYou,
        postedWithPick: false,
        replies: [],
      }}
      isYou={isYou}
      commentHref={full ? undefined : `/lists/updates/${update.postId}`}
      context={
        <p className="type-label text-fg-muted">
          Updated their {update.itemKind === "team" ? "power rankings" : `top ${update.items.length} ${update.kind.toUpperCase()}s`} · V{update.versionNo}
        </p>
      }
      footer={
        <span className="flex items-center gap-3">
          <Badge tone="outline" size="xs">Friends only</Badge>
          {full ? (
            <Link href={historyHref} className="type-label text-fg-muted underline underline-offset-2 hover:text-fg">
              See the whole history
            </Link>
          ) : null}
        </span>
      }
      thread={children}
    >
      <ol className={`px-4 pt-4 ${listGridClass(update.items.length)}`}>
        {update.items.map((item, index) => (
          <li key={item} className="min-w-0">
            <ListTile
              item={item}
              itemKind={update.itemKind}
              players={players}
              rank={index + 1}
              change={update.previousItems ? placeChange(update.previousItems, update.items, index) : undefined}
            />
          </li>
        ))}
      </ol>
    </TakeCard>
  );
}
