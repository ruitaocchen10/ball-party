import type { ComponentPropsWithoutRef, ReactNode, Ref } from "react";

/**
 * Text inputs. Square, bordered, and one of three surfaces:
 *
 * - `dark`: a field on the background. The default.
 * - `well`: a field inset into a raised dark surface (admin forms, bid bars).
 * - `panel`: a field on a cream card, where the dark surfaces would read as a hole.
 *
 * The focus state is a border change rather than a ring, matching what every
 * hand-rolled field in the app already did, so adopting these changes nothing
 * about how a focused field looks.
 */
type Variant = "dark" | "well" | "panel";

const BASE =
  "block w-full min-w-0 rounded-card border px-3 font-sans text-sm normal-case tracking-normal outline-none " +
  "transition-colors disabled:cursor-not-allowed disabled:opacity-60";

const VARIANTS: Record<Variant, string> = {
  dark: "border-line bg-surface text-fg placeholder:text-fg-muted focus:border-fg",
  well: "border-line bg-surface-raised text-fg placeholder:text-fg-muted focus:border-fg",
  panel: "border-panel-line bg-panel-shade text-panel-fg placeholder:text-panel-muted focus:border-fg-fg",
};

type Shared = { variant?: Variant };

export function Input({
  variant = "dark",
  className = "",
  ref,
  ...rest
}: Shared & ComponentPropsWithoutRef<"input"> & { ref?: Ref<HTMLInputElement> }) {
  return <input ref={ref} {...rest} className={`${BASE} ${VARIANTS[variant]} h-12 ${className}`.trim()} />;
}

export function Textarea({
  variant = "dark",
  className = "",
  ref,
  ...rest
}: Shared & ComponentPropsWithoutRef<"textarea"> & { ref?: Ref<HTMLTextAreaElement> }) {
  return <textarea ref={ref} {...rest} className={`${BASE} ${VARIANTS[variant]} resize-y py-2.5 ${className}`.trim()} />;
}

/**
 * A labelled field: the label, the control, then an optional hint and error.
 * Wraps the control in a `<label>` so clicking the text focuses it and no
 * `htmlFor`/`id` pairing is needed.
 */
export function Field({
  label,
  hint,
  error,
  variant = "dark",
  className = "",
  children,
}: {
  label: ReactNode;
  hint?: ReactNode;
  error?: ReactNode;
  /** Which surface the field sits on, for the label's colour. */
  variant?: "dark" | "panel";
  className?: string;
  children: ReactNode;
}) {
  const muted = variant === "panel" ? "text-panel-muted" : "text-fg-muted";
  return (
    <label className={`flex flex-col gap-1.5 ${className}`.trim()}>
      <span className={`type-label ${muted}`}>{label}</span>
      {children}
      {hint ? <span className={`text-xs leading-5 ${muted}`}>{hint}</span> : null}
      {error ? (
        <span role="alert" className="text-sm text-hidden-text">
          {error}
        </span>
      ) : null}
    </label>
  );
}
