import type { ReactNode } from "react";

/**
 * Concealed information. Red is the one shape in the product that means
 * "somebody knows something you don't" — the Wavelength target before the
 * reveal, a lot's fantasy points during bidding, a spot nobody has filled.
 * When the thing is revealed it becomes a <Card>.
 *
 * `label` is required and goes to screen readers: hidden information still has
 * to announce that it exists, otherwise the state is invisible rather than
 * merely secret.
 */
export function Concealed({
  label,
  children,
  className = "",
  compact = false,
}: {
  label: string;
  children?: ReactNode;
  className?: string;
  /**
   * For a chip-sized use (a hidden rating inline in a stat row) rather than a
   * card-sized one (a Wavelength target, an auction lot). The default's
   * card-scale shadow and 4px inset hairline are sized for a surface with
   * real presence; shrunk onto a chip a few px tall, that shadow blooms out
   * past the chip itself and the hairline swallows nearly all of it. Compact
   * keeps the same red weave — still unambiguously "hidden" — with a shadow
   * and hairline sized to match.
   */
  compact?: boolean;
}) {
  return (
    <div
      aria-label={children ? undefined : label}
      role={children ? undefined : "img"}
      className={`${compact ? "pattern-concealed-compact" : "pattern-concealed"} relative rounded-card bg-hidden-ink text-fg ${compact ? "shadow-concealed-compact" : "shadow-concealed"} ${className}`}
    >
      {/* the inset hairline that reads the weave as a deliberate surface */}
      <span
        aria-hidden
        className={`pointer-events-none absolute ${compact ? "inset-[2px]" : "inset-[4px]"} rounded-chip border border-fg/35`}
      />
      {children}
    </div>
  );
}
