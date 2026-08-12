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
}: {
  label: string;
  children?: ReactNode;
  className?: string;
}) {
  return (
    <div
      aria-label={children ? undefined : label}
      role={children ? undefined : "img"}
      className={`pattern-concealed relative rounded-card bg-hidden-ink text-panel shadow-concealed ${className}`}
    >
      {/* the inset hairline that reads the weave as a deliberate surface */}
      <span
        aria-hidden
        className="pointer-events-none absolute inset-[4px] rounded-[3px] border border-panel/35"
      />
      {children}
    </div>
  );
}
