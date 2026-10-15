import Link from "next/link";

import { Badge } from "@/components/foundation/ui-kit/Badge";
import { Card } from "@/components/foundation/ui-kit/Card";
import { EmptyState } from "@/components/foundation/ui-kit/EmptyState";
import { timeAgo } from "@/lib/foundation/friends/friends";
import { listPath, listTitle, sizeLabel } from "@/lib/foundation/lists/lists";
import type { ListKind, ListPlayer, ListSummary } from "@/lib/foundation/lists/types";
import { ListRows } from "./ListRows";
import { ListStartCard } from "./ListStartCard";

/**
 * A player's lists on their profile, each at the size they chose: a 32-team
 * Power Rankings shows all 32. The newest list opens first. `username` is
 * the owner when someone else is looking, which sends the History link to the
 * visitor view; the owner's own links go to the editor.
 */
export function ListSummaries({
  lists,
  players,
  username,
  emptyText,
}: {
  lists: ListSummary[];
  players: Record<string, ListPlayer>;
  username?: string | null;
  emptyText: string;
}) {
  if (!lists.length) {
    return (
      <EmptyState title="No lists yet" className="mt-3">
        {emptyText}
      </EmptyState>
    );
  }
  const newest = [...lists].sort((a, b) => b.savedAt.localeCompare(a.savedAt))[0];
  return (
    <div className="mt-3 flex flex-col gap-4">
      {lists.map((list) => (
        <Card key={list.kind}>
          <details open={list.kind === newest.kind} className="group">
            <summary className="flex cursor-pointer list-none items-baseline justify-between gap-3 px-4 pt-4 pb-2">
              <span className="font-slab text-2xl leading-none uppercase">{listTitle({ id: list.kind, itemKind: list.itemKind }, list.items.length, list.versionNo)}</span>
              <span className="flex items-center gap-2">
                <Badge tone="outline" size="xs">{sizeLabel(list.items.length, list.itemKind)}</Badge>
                <span className="type-label text-panel-muted">{timeAgo(list.savedAt)}</span>
              </span>
            </summary>
            {list.note ? <p className="px-4 pb-3 text-lg leading-7 font-medium text-panel-fg">&ldquo;{list.note}&rdquo;</p> : null}
            <div>
              <ListRows items={list.items} itemKind={list.itemKind} players={players} previous={list.previousItems ?? undefined} />
              <div className="flex items-center justify-between px-4 pb-4">
                <Link href={listPath(list.kind, username)} className="type-label text-panel-muted underline underline-offset-2 hover:text-panel-fg">
                  History · {list.versionCount} {list.versionCount === 1 ? "version" : "versions"}
                </Link>
                {!username ? (
                  <Link href={`/lists/${list.kind}`} className="type-label text-panel-fg underline underline-offset-2">Edit</Link>
                ) : null}
              </div>
            </div>
          </details>
        </Card>
      ))}
    </div>
  );
}

/**
 * The Lists tab, where a player builds their lists: every kind there is, with
 * the ones they keep showing a short preview and the rest inviting them to
 * start. Editing and history open on the list's own page.
 */
export function ListBuilder({ kinds, lists, players }: { kinds: ListKind[]; lists: ListSummary[]; players: Record<string, ListPlayer> }) {
  const byKind = new Map(lists.map((list) => [list.kind, list]));
  return (
    <ul className="mt-3 flex flex-col gap-4">
      {kinds.map((kind) => {
        const list = byKind.get(kind.id);
        if (!list) return <li key={kind.id}><ListStartCard kind={kind} players={players} /></li>;
        return (
          <li key={kind.id}>
            <Card>
              <div className="flex items-baseline justify-between gap-3 px-4 pt-4 pb-2">
                <h2 className="font-slab text-2xl leading-none uppercase">{listTitle(kind, list.items.length, list.versionNo)}</h2>
                <span className="type-label text-panel-muted">{timeAgo(list.savedAt)}</span>
              </div>
              {list.note ? <p className="px-4 pb-3 text-lg leading-7 font-medium text-panel-fg">&ldquo;{list.note}&rdquo;</p> : null}
              <div>
                <ListRows items={list.items.slice(0, 10)} itemKind={list.itemKind} players={players} previous={list.previousItems ?? undefined} size={Math.min(list.items.length, 10)} />
                {list.items.length > 10 ? (
                  <p className="px-4 pb-3 type-label text-panel-muted">+ {list.items.length - 10} more · {sizeLabel(list.items.length, list.itemKind)}</p>
                ) : null}
              </div>
              <div className="flex items-center justify-between px-4 pb-4">
                <Link href={`/lists/${kind.id}#history`} className="type-label text-panel-muted underline underline-offset-2 hover:text-panel-fg">
                  History · {list.versionCount} {list.versionCount === 1 ? "version" : "versions"}
                </Link>
                <Link href={`/lists/${kind.id}`} className="type-label text-panel-fg underline underline-offset-2">Edit</Link>
              </div>
            </Card>
          </li>
        );
      })}
    </ul>
  );
}
