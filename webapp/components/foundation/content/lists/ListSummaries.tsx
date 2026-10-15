import Link from "next/link";

import { Badge } from "@/components/foundation/ui-kit/Badge";
import { ButtonLink } from "@/components/foundation/ui-kit/Button";
import { Card } from "@/components/foundation/ui-kit/Card";
import { EmptyState } from "@/components/foundation/ui-kit/EmptyState";
import { timeAgo } from "@/lib/foundation/friends/friends";
import { listPath, sizeLabel } from "@/lib/foundation/lists/lists";
import type { ListKind, ListPlayer, ListSummary } from "@/lib/foundation/lists/types";
import { ListRows } from "./ListRows";

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
            <summary className="flex cursor-pointer list-none items-baseline justify-between gap-3 px-3 pt-3 pb-3">
              <span className="font-slab text-2xl leading-none uppercase">{list.label}</span>
              <span className="flex items-center gap-2">
                <Badge tone="outline" size="xs">{sizeLabel(list.items.length, list.itemKind)}</Badge>
                <span className="type-label text-panel-muted">v{list.versionNo} · {timeAgo(list.savedAt)}</span>
              </span>
            </summary>
            <div className="border-t border-panel-line">
              <ListRows items={list.items} itemKind={list.itemKind} players={players} />
              <div className="flex items-center justify-between border-t border-panel-line px-3 py-3">
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
        return (
          <li key={kind.id}>
            <Card>
              <div className="flex items-baseline justify-between gap-3 px-3 pt-3 pb-3">
                <h2 className="font-slab text-2xl leading-none uppercase">{kind.label}</h2>
                <span className="type-label text-panel-muted">
                  {list ? `v${list.versionNo} · ${timeAgo(list.savedAt)}` : kind.sizes.map((size) => sizeLabel(size, kind.itemKind)).join(" · ")}
                </span>
              </div>
              {list ? (
                <>
                  <div className="border-t border-panel-line">
                    <ListRows items={list.items.slice(0, 3)} itemKind={list.itemKind} players={players} />
                    {list.items.length > 3 ? (
                      <p className="border-t border-panel-line px-3 py-2 type-label text-panel-muted">+ {list.items.length - 3} more · {sizeLabel(list.items.length, list.itemKind)}</p>
                    ) : null}
                  </div>
                  <div className="flex items-center justify-between border-t border-panel-line px-3 py-3">
                    <Link href={`/lists/${kind.id}#history`} className="type-label text-panel-muted underline underline-offset-2 hover:text-panel-fg">
                      History · {list.versionCount} {list.versionCount === 1 ? "version" : "versions"}
                    </Link>
                    <Link href={`/lists/${kind.id}`} className="type-label text-panel-fg underline underline-offset-2">Edit</Link>
                  </div>
                </>
              ) : (
                <div className="border-t border-panel-line px-3 py-3">
                  <p className="text-sm leading-6 text-panel-soft">
                    {kind.itemKind === "team" ? "Rank the teams. Friends can see it and reply when you change it." : `Rank your top ${kind.sizes[0]}. Friends can see it and reply when you change it.`}
                  </p>
                  <div className="mt-3 max-w-[12rem]">
                    <ButtonLink href={`/lists/${kind.id}`} variant="ink" size="sm">Start your list</ButtonLink>
                  </div>
                </div>
              )}
            </Card>
          </li>
        );
      })}
    </ul>
  );
}
