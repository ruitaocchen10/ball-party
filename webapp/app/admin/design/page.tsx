import type { Metadata } from "next";

import { TokenSwatch } from "@/components/admin/TokenSwatch";

export const metadata: Metadata = { title: "Design tokens" };

// Names and one-line uses only: each swatch reads its value back from the CSS
// variable, so a colour is defined once, in globals.css. Keep this list in step
// with docs/design/design-system.md (and with Theme.swift, which tokens.test.ts checks).
const COLORS: { group: string; tokens: [name: string, use: string][] }[] = [
  {
    group: "Background",
    tokens: [
      ["surface", "The page background. Also a field's fill on the background."],
      ["surface-raised", "Inset wells: inputs inside a raised surface, bid bars, dialogs, empty states."],
    ],
  },
  {
    group: "Panels",
    tokens: [
      ["panel", "The raised surface: cards, menus, chips."],
      ["panel-shade", "A subdued band inside a panel."],
      ["panel-fg", "Primary text on a panel."],
      ["panel-muted", "Secondary text on a panel."],
      ["panel-soft", "Body copy on a panel."],
      ["panel-line", "Borders and rules on a panel."],
      ["panel-hover", "A pressable panel's hover."],
      ["panel-ink-hover", "An ink button's hover."],
    ],
  },
  {
    group: "Concealed",
    tokens: [
      ["hidden", "Concealed values and unfilled spots, as a surface."],
      ["hidden-text", "The same red, lifted for the background. Also error text."],
      ["hidden-ink", "The same red, darkened: a hovered or pressed red surface."],
    ],
  },
  {
    group: "Grades",
    tokens: [
      ["grade-elite", "Revealed grade. Deliberately not red."],
      ["grade-strong", "Revealed grade."],
      ["grade-even", "Revealed grade."],
      ["grade-rough", "Revealed grade."],
    ],
  },
  {
    group: "Text on the background",
    tokens: [
      ["fg", "Text on the background."],
      ["fg-muted", "Secondary text on the background."],
      ["line", "Borders and rules on the background."],
    ],
  },
];

const LABELS = [
  ["type-label-xs", "9px · chips and dense metadata"],
  ["type-label", "10px · section labels, eyebrows"],
  ["type-label-lg", "11px · labels with more presence"],
] as const;

const SHADOWS = [
  ["shadow-card", "Raised panels"],
  ["shadow-well", "Passive surfaces"],
  ["shadow-concealed", "Red concealed surfaces"],
] as const;

/** Every design token on one page, for checking what a name looks like. Admin only, via the /admin layout. */
export default function AdminDesignPage() {
  return (
    <div className="mx-auto w-full max-w-5xl px-4 pt-8 pb-16 sm:px-6">
      <h1 className="font-slab text-2xl leading-none uppercase">Design tokens</h1>
      <p className="mt-2 max-w-[60ch] text-sm text-fg-muted">
        What each token looks like in the browser. The rules are in docs/design/design-system.md.
      </p>

      <h2 className="mt-10 font-slab text-xl leading-none uppercase">Colors</h2>
      <div className="mt-4 grid gap-x-10 gap-y-8 md:grid-cols-2">
        {COLORS.map(({ group, tokens }) => (
          <section key={group}>
            <h3 className="type-label font-semibold text-hidden-text">{group}</h3>
            <ul className="mt-2 border-t border-line">
              {tokens.map(([name, use]) => (
                <TokenSwatch key={name} name={name} use={use} />
              ))}
            </ul>
          </section>
        ))}
      </div>

      <h2 className="mt-12 font-slab text-xl leading-none uppercase">Type</h2>
      <ul className="mt-4 space-y-3 border-t border-line pt-4">
        <li>
          <p className="font-slab text-4xl leading-none uppercase">Bebas Neue</p>
          <p className="mt-1 type-label text-fg-muted">font-slab · headings, button labels, big numbers</p>
        </li>
        <li>
          <p className="text-lg">Barlow — the quick brown fox jumps over the lazy dog.</p>
          <p className="mt-1 type-label text-fg-muted">font-sans · body text</p>
        </li>
        <li>
          <p className="font-mono text-lg">JetBrains Mono 0123456789</p>
          <p className="mt-1 type-label text-fg-muted">font-mono · labels, metadata, codes, tabular numbers</p>
        </li>
      </ul>

      <ul className="mt-6 space-y-2 border-t border-line pt-4">
        {LABELS.map(([cls, note]) => (
          <li key={cls} className="flex items-baseline gap-4">
            <span className={`${cls} w-44 shrink-0`}>Section label</span>
            <span className="font-mono text-sm text-fg-muted">
              {cls} · {note}
            </span>
          </li>
        ))}
      </ul>

      <h2 className="mt-12 font-slab text-xl leading-none uppercase">Depth</h2>
      <ul className="mt-4 flex flex-wrap gap-6 border-t border-line pt-6">
        {SHADOWS.map(([cls, note]) => (
          <li key={cls}>
            <div
              className={`${cls} h-20 w-36 ${cls === "shadow-card" ? "bg-panel" : cls === "shadow-concealed" ? "bg-hidden" : "bg-surface-raised"}`}
            />
            <p className="mt-3 font-mono text-sm">{cls}</p>
            <p className="text-sm text-fg-muted">{note}</p>
          </li>
        ))}
      </ul>
    </div>
  );
}
