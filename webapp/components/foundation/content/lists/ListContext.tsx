import { timeAgo } from "@/lib/foundation/friends/friends";

/**
 * The editor page's right rail, the list's counterpart of a prompt's "About
 * this prompt": how saving works and where this list stands.
 */
export function ListContext({ versionNo, savedAt, versionCount }: { versionNo: number | null; savedAt: string | null; versionCount: number }) {
  return (
    <aside aria-label="About this list" className="xl:sticky xl:top-[92px] xl:self-start">
      <div className="rounded-card border border-line bg-surface-raised p-4 shadow-well">
        <p className="type-label font-semibold text-fg-muted">List details</p>
        <h2 className="mt-1 font-slab text-[27px] leading-none text-fg uppercase">About this list</h2>
        <div className="mt-4 border-t border-line">
          <div className="border-b border-line py-3.5">
            <p className="type-label text-fg-muted">Status</p>
            <p className="mt-1.5 text-sm leading-6 text-fg">
              {versionNo === null || savedAt === null
                ? "Not started yet. Your first save starts the history."
                : `Version ${versionNo}, saved ${timeAgo(savedAt)}. ${versionCount} ${versionCount === 1 ? "version" : "versions"} in your history.`}
            </p>
          </div>
          <div className="border-b border-line py-3.5">
            <p className="type-label text-fg-muted">Saving</p>
            <p className="mt-1.5 text-sm leading-6 text-fg">
              Every save is a new version that stays in your history. You can save once a day. A save in the first 10 minutes fixes the last version instead.
            </p>
          </div>
          <div className="py-3.5">
            <p className="type-label text-fg-muted">Sharing</p>
            <p className="mt-1.5 text-sm leading-6 text-fg">
              Friends see your update, what moved and your take, and can reply. Turn sharing off to save quietly.
            </p>
          </div>
        </div>
      </div>
    </aside>
  );
}
