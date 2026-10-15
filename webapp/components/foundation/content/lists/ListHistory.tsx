import Link from "next/link";

import { Badge } from "@/components/foundation/ui-kit/Badge";
import { biggestMoves, movedCount } from "@/lib/foundation/lists/lists";
import type { ListPlayer, ListVersion } from "@/lib/foundation/lists/types";
import { timeAgo } from "@/lib/foundation/friends/friends";
import { ListRows } from "./ListRows";

function itemName(item: string, itemKind: "team" | "player", players: Record<string, ListPlayer>) {
  return itemKind === "team" ? item : (players[item]?.name ?? "A player");
}

/** "DET ▲3 · SF ▼2" for a version, against the one before it. */
function movesLine(previous: string[] | null, items: string[], itemKind: "team" | "player", players: Record<string, ListPlayer>) {
  if (!previous) return "First version";
  const moves = biggestMoves(previous, items, 3);
  if (!moves.length) return "No change in order";
  const named = moves.map((move) => `${itemName(move.item, itemKind, players)} ${move.change === null ? "new" : move.change > 0 ? `▲${move.change}` : `▼${-move.change}`}`);
  const rest = movedCount(previous, items) - moves.length;
  return rest > 0 ? `${named.join(" · ")} · ${rest} more` : named.join(" · ");
}

/**
 * Every saved version of one list, newest first. A version is a stop on the
 * timeline: when, what moved, the note, and how it got there. `close` is true
 * for the owner and their friends, who also see the notes and which versions
 * were shared; for anyone else the database leaves those out.
 */
export function ListHistory({
  versions,
  itemKind,
  players,
  close,
}: {
  versions: ListVersion[];
  itemKind: "team" | "player";
  players: Record<string, ListPlayer>;
  close: boolean;
}) {
  return (
    <ol aria-label="Version history" className="relative flex flex-col gap-3 border-l border-line pl-5">
      {versions.map((version, index) => {
        const previous = versions[index + 1]?.items ?? null;
        return (
          <li key={version.id} className="relative">
            <span
              aria-hidden
              className={`absolute top-5 -left-[1.6rem] h-2.5 w-2.5 rounded-full border-2 ${version.isCurrent ? "border-hidden bg-hidden" : "border-fg-muted bg-surface"}`}
            />
            <div className="rounded-card bg-panel p-3 text-panel-fg shadow-card">
              <div className="flex items-baseline justify-between gap-3">
                <h3 className="font-slab text-xl leading-none uppercase">
                  Version {version.versionNo}{version.isCurrent ? " · Now" : ""}
                </h3>
                <span className="type-label text-panel-muted">{timeAgo(version.savedAt)}</span>
              </div>
              {version.note ? <p className="mt-2 text-[15px] leading-6 text-panel-soft">&ldquo;{version.note}&rdquo;</p> : null}
              <p className="mt-2 type-label text-panel-muted">{movesLine(previous, version.items, itemKind, players)}</p>
              <div className="mt-2 flex flex-wrap items-center gap-1.5">
                {version.source === "prompt" ? <Badge tone="outline" size="xs">Prompt answer</Badge> : null}
                {close && version.source === "edit" ? (
                  version.updatePostId ? <Badge tone="soft" size="xs">Shared with friends</Badge> : <Badge tone="outline" size="xs">Saved quietly</Badge>
                ) : null}
                {close && version.updatePostId ? (
                  <Link href={`/lists/updates/${version.updatePostId}`} className="type-label-xs text-panel-muted underline underline-offset-2 hover:text-panel-fg">
                    Replies
                  </Link>
                ) : null}
              </div>
              <details className="mt-2 group">
                <summary className="cursor-pointer list-none type-label text-panel-muted hover:text-panel-fg">
                  <span className="group-open:hidden">Show the list</span>
                  <span className="hidden group-open:inline">Hide the list</span>
                </summary>
                <div className="mt-2 -mx-3 border-t border-panel-line">
                  <ListRows items={version.items} itemKind={itemKind} players={players} previous={previous} />
                </div>
              </details>
            </div>
          </li>
        );
      })}
    </ol>
  );
}
