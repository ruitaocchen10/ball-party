import type { ReactNode } from "react";

/**
 * A face-down card. Red is the back of a card, so this is the one shape in the
 * product that means "somebody knows something you don't" — the unopened pack,
 * the Wavelength target before the reveal, a lot's fantasy points during
 * bidding. When the thing is revealed it becomes a <Card>.
 *
 * `label` is required and goes to screen readers: hidden information still has
 * to announce that it exists, otherwise the state is invisible rather than
 * merely secret.
 */
export function CardBack({
  label,
  children,
  className = "",
}: {
  label: string;
  children?: ReactNode;
  className?: string;
}) {
  return (
    <div
      aria-label={children ? undefined : label}
      role={children ? undefined : "img"}
      className={`pattern-back relative rounded-card bg-hidden shadow-back ${className}`}
    >
      {/* the inset hairline every printed card back has */}
      <span
        aria-hidden
        className="pointer-events-none absolute inset-[4px] rounded-[3px] border border-stock/35"
      />
      {children}
    </div>
  );
}
