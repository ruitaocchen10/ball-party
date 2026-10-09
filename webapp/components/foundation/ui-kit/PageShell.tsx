import type { ComponentPropsWithoutRef, ReactNode } from "react";

/**
 * The `<main>` every page renders. It owns the page's width, gutters and
 * vertical padding, so a page never spells those out and two pages of the same
 * kind can't drift apart.
 *
 * - `dashboard`: the app workspace (Home, Party, Solo, Profile…). Wide,
 *   centered, with room for the top bar. Its children go in a single 760px
 *   column (`.app-column`), so a page header and the content under it share
 *   one width. Pass `rail` for a secondary panel beside the column from `xl`
 *   (the rail decides its own visibility below that). See `.app-page` and
 *   `.app-layout` in globals.css.
 * - `form`: one centered card-sized column, for sign-in and short
 *   single-purpose screens. `size="md"` for a slightly roomier one.
 * - `narrow`: a readable column of stacked sections, for a game's waiting,
 *   setup and results screens.
 * - `prose`: long-form text (Privacy, Support).
 * - `game`: the full-width play surface. `locked` fits it to the viewport with
 *   no page scroll (an in-match screen); unlocked it scrolls like any page and
 *   keeps the roomier responsive gutters (the lobby).
 *
 * Sidebar clearance is not handled here: globals.css pads `body` whenever a
 * rail is mounted, so every variant centers correctly beside it.
 */
type Variant = "dashboard" | "form" | "narrow" | "prose" | "game";

type Props = ComponentPropsWithoutRef<"main"> & {
  variant: Variant;
  /** `form` only. */
  size?: "sm" | "md";
  /** `game` only. */
  locked?: boolean;
  /** `dashboard` only: a secondary panel beside the column from `xl`. */
  rail?: ReactNode;
};

const BASE: Record<Variant, string> = {
  dashboard: "app-page flex-1",
  narrow: "mx-auto flex w-full max-w-2xl flex-1 flex-col gap-4 px-4 py-8",
  prose: "mx-auto w-full max-w-2xl px-6 py-16",
  form: "mx-auto flex min-h-dvh w-full flex-col justify-center gap-4 px-6 py-16",
  game: "flex w-full flex-1 flex-col px-4 pb-16 sm:px-6 lg:px-8 lg:pb-20",
};

const GAME_LOCKED = "mx-auto flex w-full min-h-0 flex-1 flex-col gap-4 overflow-hidden px-4 pt-3 pb-4";

export function PageShell({ variant, size = "sm", locked = false, rail, className = "", children, ...rest }: Props) {
  const base =
    variant === "form"
      ? `${BASE.form} ${size === "md" ? "max-w-md" : "max-w-sm"}`
      : variant === "game" && locked
        ? GAME_LOCKED
        : BASE[variant];
  return (
    <main {...rest} className={`${base} ${className}`.trim()}>
      {variant === "dashboard" ? (
        rail ? (
          <div className="app-layout">
            <div className="min-w-0">{children}</div>
            {rail}
          </div>
        ) : (
          <div className="app-column">{children}</div>
        )
      ) : (
        children
      )}
    </main>
  );
}
