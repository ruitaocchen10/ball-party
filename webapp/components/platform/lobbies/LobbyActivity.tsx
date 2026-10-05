import { History, Trophy } from "lucide-react";

import { activityLabel, timeAgo, type RoomActivity } from "@/lib/platform/lobbies/activity";

/** The room's latest completed games, rather than another view of its roster. */
export function LobbyActivity({ activity }: { activity: RoomActivity[] }) {
  return (
    <section aria-labelledby="activity-heading" className="flex flex-col gap-3">
      <div>
        <p className="type-label text-fg-muted">This room</p>
        <h2 id="activity-heading" className="mt-1 font-slab text-2xl leading-none uppercase">Activity</h2>
      </div>

      {activity.length === 0 ? (
        <div className="rounded-card bg-surface-raised px-3 py-4 text-center ring-1 ring-line ring-inset">
          <History aria-hidden className="mx-auto h-4 w-4 text-fg-muted" strokeWidth={1.5} />
          <p className="mt-2 text-sm leading-5 text-fg-muted">The first game will make the history.</p>
        </div>
      ) : (
        <ol className="flex flex-col gap-1.5">
          {activity.map((item) => (
            <li key={item.id} className="flex items-start gap-2 rounded-card bg-surface-raised px-2.5 py-2.5 ring-1 ring-line ring-inset">
              <Trophy aria-hidden className="mt-0.5 h-3.5 w-3.5 shrink-0 text-panel" strokeWidth={1.5} />
              <div className="min-w-0 flex-1">
                <p className="text-sm leading-5 text-fg">{activityLabel(item)}</p>
                <time dateTime={item.endedAt} className="type-label-xs text-fg-muted">
                  {timeAgo(item.endedAt)}
                </time>
              </div>
            </li>
          ))}
        </ol>
      )}
    </section>
  );
}
