"use client";

import { useSyncExternalStore } from "react";

const subscribe = () => () => {};

/**
 * One colour token, drawn with its own CSS variable and labelled with the value
 * the browser actually resolves it to. Reading the value back rather than
 * restating it means this page can't disagree with globals.css.
 */
export function TokenSwatch({ name, use }: { name: string; use: string }) {
  // Nothing changes at runtime, so there is nothing to subscribe to: the store
  // is only here to read the browser's value after hydration (empty on the server).
  const value = useSyncExternalStore(
    subscribe,
    () => getComputedStyle(document.documentElement).getPropertyValue(`--${name}`).trim(),
    () => "",
  );

  return (
    <li className="flex items-center gap-3 border-b border-line py-2.5 last:border-b-0">
      <span aria-hidden className="h-10 w-14 shrink-0 border border-line" style={{ background: `var(--${name})` }} />
      <div className="min-w-0 flex-1">
        <p className="font-mono text-sm">
          {name} <span className="text-fg-muted">{value}</span>
        </p>
        <p className="text-sm text-fg-muted">{use}</p>
      </div>
    </li>
  );
}
