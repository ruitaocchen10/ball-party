import type { CSSProperties, ReactNode } from "react";

/**
 * A presentational slot-machine reel. Games supply their own decoys and own
 * the moment a result becomes usable; this component only makes a supplied
 * sequence travel to its last row.
 *
 * The final item must be the landed result. Keeping it as a physical row
 * means the animation and the eventual resting state agree without relying
 * on an animation-end event. Reduced-motion users get an explicit waiting
 * state instead of a reel frozen on a decoy.
 */
export function SlotReel<T>({
  items,
  durationMs,
  reelKey,
  viewportClassName,
  rowClassName,
  renderItem,
  itemKey,
  waitingLabel = "Spinning…",
}: {
  items: readonly T[];
  durationMs: number;
  /** Change this to remount and replay the CSS animation. */
  reelKey: string | number;
  viewportClassName: string;
  rowClassName: string;
  renderItem: (item: T, index: number) => ReactNode;
  itemKey: (item: T, index: number) => string | number;
  waitingLabel?: string;
}) {
  return (
    <div className={`${viewportClassName} overflow-hidden`} aria-hidden="true">
      <div
        key={reelKey}
        className="animate-reel-spin motion-reduce:hidden flex flex-col"
        style={{ "--reel-count": items.length, animationDuration: `${durationMs}ms` } as CSSProperties}
      >
        {items.map((item, index) => (
          <span key={itemKey(item, index)} className={`flex shrink-0 ${rowClassName}`}>
            {renderItem(item, index)}
          </span>
        ))}
      </div>
      <p className={`hidden ${rowClassName} items-center justify-center font-mono text-xs text-panel-muted uppercase motion-reduce:flex`}>
        {waitingLabel}
      </p>
    </div>
  );
}
