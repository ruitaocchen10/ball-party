"use client";

import { useLayoutEffect, useState, type HTMLAttributes, type RefObject } from "react";
import { createPortal } from "react-dom";

type Rect = { top: number; left: number; width: number };

/**
 * A dropdown list that hangs under `anchor` and is portaled to <body>.
 *
 * Cards and composers here are `overflow-hidden` (they clip a corner strip or
 * a cut-corner silhouette), so a list that is an ordinary absolutely
 * positioned child gets cropped at the card's edge. Rendering it in a portal
 * with fixed coordinates lets it float above that; the coordinates are
 * recomputed while it is open so a scroll or resize can't strand it.
 *
 * Renders nothing while closed. The consumer owns focus and selection —
 * this is only the floating box.
 */
export function AnchoredList({
  anchor,
  open,
  className = "",
  children,
  ...props
}: { anchor: RefObject<HTMLElement | null>; open: boolean } & HTMLAttributes<HTMLUListElement>) {
  const [rect, setRect] = useState<Rect | null>(null);

  useLayoutEffect(() => {
    if (!open) return;
    const place = () => {
      const box = anchor.current?.getBoundingClientRect();
      if (box) setRect({ top: box.bottom, left: box.left, width: box.width });
    };
    place();
    window.addEventListener("resize", place);
    window.addEventListener("scroll", place, true);
    return () => {
      window.removeEventListener("resize", place);
      window.removeEventListener("scroll", place, true);
    };
  }, [open, anchor]);

  if (!open || !rect) return null;
  return createPortal(
    <ul
      {...props}
      style={{ position: "fixed", top: rect.top + 4, left: rect.left, width: rect.width }}
      className={`z-50 max-h-72 overflow-y-auto border border-line bg-surface-raised shadow-[0_10px_24px_rgb(0_0_0/0.4)] ${className}`}
    >
      {children}
    </ul>,
    document.body,
  );
}
