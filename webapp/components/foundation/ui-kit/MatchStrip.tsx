"use client";

import { useState, type ReactNode, type Ref } from "react";
import { GeneratedAvatar } from "@/components/foundation/identity/GeneratedAvatar";

/**
 * The shared shell behind every "what's happened, what's now, what's next"
 * horizontal strip in a live match — auction's LotStrip and Wavelength's round
 * strip both render one of these per lot/round. They began as separate,
 * hand-rolled `<ol>`s of fixed-size cells with no vertical overflow
 * guard; a cell could stack a full-length name, an outcome line, and
 * a hit badge past its own fixed height and spill into whatever sat below it.
 * This shell makes that impossible by construction — every cell gets
 * `overflow-hidden`, every text line truncates, and a hit reads as a pill
 * instead of a line that competes for vertical room — so the two games'
 * strips can no longer visually drift apart just because one game's content
 * runs longer than the other's.
 */
// Tall enough for the on-the-clock/settled anatomy every cell now shares —
// a label, an enlarged avatar, a name, and (when there's one) an outcome
// line plus a hit badge — with room to spare, since `overflow-hidden` below
// is the actual guarantee here, not this number.
export const STRIP_CELL_HEIGHT = "h-[104px]";
const STRIP_CELL_BASE = `${STRIP_CELL_HEIGHT} shrink-0 overflow-hidden flex px-1.5 py-2`;

export function MatchStrip({
  ariaLabel,
  listRef,
  children,
}: {
  ariaLabel: string;
  listRef?: Ref<HTMLOListElement>;
  children: ReactNode;
}) {
  return (
    <ol
      ref={listRef}
      aria-label={ariaLabel}
      className="flex shrink-0 gap-1.5 overflow-x-auto scroll-smooth pb-1 [scrollbar-width:thin]"
    >
      {children}
    </ol>
  );
}

type Tone = "settled" | "current" | "upcoming";

// "settled" and "upcoming" pin their label to the top edge and their
// name/status to the bottom edge (justify-between) rather than centering
// the whole stack as one block — the label reads as a header, not as
// whatever happens to be the first line of a floating group. The trade-off:
// a cell with more lines (a spin caption) packs tighter than a sparser one,
// so the avatar in between sits a few px lower on a sparse cell than a
// dense one — content-driven breathing room, not a fixed grid position. A
// hit/result callout stays out of that count entirely: `StripCellMediaBadge`
// floats it above the avatar/portrait rather than adding a line, so it no
// longer sways this rhythm at all. "current" carries the on-the-clock
// highlight and, alone among the three, lays out sideways — an avatar
// beside its text stack, the same asymmetry a snake draft board gives its
// one highlighted pick.
const TONE_CLASS: Record<Tone, string> = {
  // A border, not just the background delta from the page — `surface-raised`
  // alone is only a few percent lighter than the page's own `surface`, easy
  // to lose entirely once cells are this small and packed edge to edge in a
  // row. "current" and "upcoming" already had one; this brings "settled" in
  // line with them instead of being the one tone with no defined edge.
  settled:
    "flex-col justify-between rounded-card border border-line bg-surface-raised shadow-well",
  current:
    "flex-row items-center gap-2.5 rounded-card border border-fg/45 bg-fg/10 px-2.5",
  upcoming:
    "flex-col items-center justify-between rounded-card border border-line bg-transparent",
};

export function StripCell({
  tone,
  width,
  ariaLabel,
  className = "",
  ref,
  children,
}: {
  tone: Tone;
  width: number;
  ariaLabel?: string;
  className?: string;
  ref?: Ref<HTMLLIElement>;
  children: ReactNode;
}) {
  return (
    <li
      ref={ref}
      aria-current={tone === "current" ? "step" : undefined}
      aria-label={ariaLabel}
      style={{ width }}
      className={`${STRIP_CELL_BASE} ${TONE_CLASS[tone]} ${className}`}
    >
      {children}
    </li>
  );
}

/** The top mono line a settled cell opens with — a short left label and a tabular right value (round number, price, whatever the game's own header needs). Always one line, both sides truncate/clip rather than wrap. */
export function StripCellTop({
  left,
  right,
}: {
  left: ReactNode;
  right: ReactNode;
}) {
  return (
    <p className="flex items-baseline justify-between gap-1 type-label-xs leading-none text-fg-muted">
      <span className="truncate">{left}</span>
      <span className="shrink-0 tabular-nums">{right}</span>
    </p>
  );
}

/** A circular media slot — a headshot or a franchise mark — centered above the name the way both games already treat identity art. */
export function StripCellMedia({
  children,
  className = "h-7 w-7",
  square = false,
}: {
  children: ReactNode;
  className?: string;
  /** Rounded-rectangle instead of a circle: for a photo, where avatars stay round. */
  square?: boolean;
}) {
  return (
    <span
      className={`mx-auto mt-1 block shrink-0 overflow-hidden ${square ? "rounded-chip" : "rounded-full"} bg-panel-shade ${className}`}
    >
      {children}
    </span>
  );
}

/**
 * The identity a cell leads with when there's no drafted player to show a
 * headshot of yet — whose turn a round is, which is public the moment it
 * opens, even on games where what that seat picks stays concealed until it's
 * theirs to reveal. Same "mine is red, everyone else is
 * neutral" convention RosterBoard's own seat avatar already carries, just
 * enlarged here to actually lead the cell the way ESPN's own team icon does.
 */
export function StripCellAvatar({
  name,
  avatarUrl = null,
  mine = false,
  big = false,
  muted = false,
}: {
  name: string;
  /** The player's own profile photo, when they've set one. Falls back to the
   * initials chip below on a missing URL or a load failure — the same
   * posture PlayerPortrait takes for a missing/broken headshot. */
  avatarUrl?: string | null;
  mine?: boolean;
  big?: boolean;
  muted?: boolean;
}) {
  const [imageFailed, setImageFailed] = useState(false);
  const size = big ? "h-10 w-10 text-base" : "h-8 w-8 text-sm";

  if (avatarUrl && !imageFailed) {
    return (
      <img
        src={avatarUrl}
        alt=""
        onError={() => setImageFailed(true)}
        className={`mx-auto mt-1 shrink-0 rounded-full object-cover ${size} ${muted ? "opacity-55" : ""}`}
      />
    );
  }

  return (
    <span
      aria-hidden="true"
      className={`mx-auto mt-1 flex shrink-0 items-center justify-center overflow-hidden rounded-full ${size} ${mine ? "ring-2 ring-hidden" : ""} ${muted ? "opacity-55" : ""}`}
    >
      <GeneratedAvatar name={name} size={big ? 40 : 32} className="h-full w-full" />
    </span>
  );
}

/** The current cell's right-hand text stack, sitting beside its avatar rather than under it. */
export function StripCellTextColumn({ children }: { children: ReactNode }) {
  return (
    <div className="flex min-w-0 flex-1 flex-col justify-center">
      {children}
    </div>
  );
}

/** The identity line — always one truncated slab line, never a name a cell has to hope stays short. */
export function StripCellName({
  children,
  center = false,
}: {
  children: ReactNode;
  center?: boolean;
}) {
  return (
    <p
      className={`mt-1 truncate font-slab text-[11px] leading-none uppercase ${center ? "text-center" : ""}`}
    >
      {children}
    </p>
  );
}

/** The status/outcome caption below the name — mono, muted, one line, optionally led by a small icon (a logo, a portrait). */
export function StripCellCaption({
  children,
  center = false,
  icon,
}: {
  children: ReactNode;
  center?: boolean;
  icon?: ReactNode;
}) {
  return (
    <p
      className={`mt-1 flex items-center gap-1 truncate font-mono text-[9px] leading-none tracking-[0.08em] text-fg-muted uppercase ${center ? "justify-center" : ""}`}
    >
      {icon}
      <span className="truncate">{children}</span>
    </p>
  );
}

/** A hit/result callout as a small pill, not a third stacked text line — the thing that let a settled cell overflow its own box in the first place. */
export function StripCellBadge({ children }: { children: ReactNode }) {
  return (
    <span className="mt-1 w-fit shrink-0 rounded-full bg-hidden/15 px-1.5 py-0.5 font-mono text-[8px] leading-none tracking-[0.06em] text-hidden-text uppercase">
      {children}
    </span>
  );
}

/**
 * A hit/result callout pinned to the bottom edge of a cell's avatar or
 * portrait — between the icon and the name below it — instead of stacked as
 * its own line under the name. The same information `StripCellBadge`
 * carries, but off the text column entirely, so a cell's height and
 * internal rhythm no longer depend on whether that round happens to have
 * one. Give the avatar/portrait a `relative w-fit` wrapper and drop this in
 * as its sibling; it overlaps the wrapper's bottom edge rather than adding a
 * line to it. A solid fill (not `StripCellBadge`'s tinted one) since this
 * sits on top of photo art rather than the cell's own background.
 */
export function StripCellMediaBadge({ children }: { children: ReactNode }) {
  return (
    <span className="absolute -bottom-1 left-1/2 z-10 w-max -translate-x-1/2 rounded-full bg-hidden px-1.5 py-0.5 font-mono text-[7px] leading-none tracking-[0.05em] text-fg uppercase shadow-well">
      {children}
    </span>
  );
}

/** The on-the-clock cell's headline — "R6 · CB" / "Lot 6 / 20" — `meta` carries the game's own trailing detail so the separator stays whatever that game already uses. */
export function StripCellTitle({
  children,
  meta,
}: {
  children: ReactNode;
  meta?: ReactNode;
}) {
  return (
    <p className="truncate font-slab text-base leading-none uppercase">
      {children}
      {meta ? (
        <span className="ml-1.5 font-mono text-[10px] tracking-[0.1em] text-fg-muted">
          {meta}
        </span>
      ) : null}
    </p>
  );
}

/** Shortens a full name to "F. Last" once it has more than one part — the trick that keeps auction's settled cells from ever reaching their own fixed height, now shared so every strip's cells get the same headroom. */
export function abbreviate(name: string): string {
  const parts = name.trim().split(/\s+/);
  if (parts.length < 2) return name;
  return `${parts[0][0]}. ${parts.slice(1).join(" ")}`;
}
