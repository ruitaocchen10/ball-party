/**
 * The BP monogram: the app's own display face (Bebas Neue) with a single
 * stitch tucked into the counter of the P, the way a ball's seam is a single
 * thread through the leather rather than a whole lace pattern.
 *
 * fontSize/x/y are one linked system, not independent knobs:
 *  - fontSize=88 is the original 40 bumped 2.2x so the letters actually fill
 *    the icon instead of sitting small in the middle of it.
 *  - y=80.8 is the baseline that keeps that bigger cap height (61.6) centered
 *    in the 100-tall box.
 *  - x=53.1 is the same 2.2x bump applied to the old optical-center offset
 *    (51.4, i.e. +1.4 off true-center 50): "BP" isn't visually centered at
 *    its own geometric midpoint because B reads heavier than P, and that
 *    offset scales with the letters, not with the viewBox. Don't reset it to
 *    50, and don't change fontSize/y without rescaling this too.
 *
 * Text renders with the CSS font-slab variable rather than as a baked path,
 * consistent with how the rest of the app trusts next/font (self-hosted, no
 * runtime fetch) instead of pre-converting display type to outlines.
 */
export function BrandMark({ className = "h-6 w-6" }: { className?: string }) {
  return (
    <svg viewBox="0 0 100 100" className={className} aria-hidden="true">
      <text
        x="53.1"
        y="80.8"
        textAnchor="middle"
        fontFamily="var(--font-slab), sans-serif"
        fontSize="88"
        fill="currentColor"
      >
        BP
      </text>
      <g stroke="var(--hidden)" strokeWidth="1.5" strokeLinecap="round">
        <line x1="70.04" y1="35.66" x2="73.64" y2="39.26" />
        <line x1="73.64" y1="35.66" x2="70.04" y2="39.26" />
      </g>
    </svg>
  );
}
