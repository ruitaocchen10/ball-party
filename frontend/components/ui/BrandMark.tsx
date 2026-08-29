/**
 * The BP monogram: the app's own display face (Bebas Neue) over a stitched
 * seam, the way a baseball's actual seam is laced — paired diagonal threads
 * following the curve, not a dashed line standing in for one.
 *
 * The stitch curve is geometrically centered on x=50, but "BP" isn't visually
 * centered at its own geometric midpoint — B reads heavier than P — so the
 * text sits at x=51.4, not x=50. That number came from rasterizing both
 * layers and comparing their ink-weighted centroids, not from eyeballing it;
 * don't "simplify" it back to 50.
 *
 * Text renders with the CSS font-slab variable rather than as a baked path,
 * consistent with how the rest of the app trusts next/font (self-hosted, no
 * runtime fetch) instead of pre-converting display type to outlines.
 */
export function BrandMark({ className = "h-6 w-6" }: { className?: string }) {
  return (
    <svg viewBox="0 0 100 100" className={className} aria-hidden="true">
      <text
        x="51.4"
        y="54"
        textAnchor="middle"
        fontFamily="var(--font-slab), sans-serif"
        fontSize="40"
        fill="currentColor"
      >
        BP
      </text>
      <g stroke="var(--hidden)" strokeWidth="1.7" strokeLinecap="round">
        <line x1="29.2" y1="72.5" x2="31.4" y2="78.1" />
        <line x1="27.3" y1="75.3" x2="33.3" y2="75.3" />
        <line x1="34.6" y1="76.0" x2="37.6" y2="81.2" />
        <line x1="33.1" y1="79.1" x2="39.0" y2="78.2" />
        <line x1="39.9" y1="78.6" x2="43.8" y2="83.1" />
        <line x1="39.0" y1="81.8" x2="44.7" y2="79.9" />
        <line x1="47.5" y1="80.3" x2="52.5" y2="83.7" />
        <line x1="47.5" y1="83.7" x2="52.5" y2="80.3" />
        <line x1="55.3" y1="79.9" x2="61.0" y2="81.8" />
        <line x1="56.2" y1="83.1" x2="60.1" y2="78.6" />
        <line x1="61.0" y1="78.2" x2="66.9" y2="79.1" />
        <line x1="62.4" y1="81.2" x2="65.4" y2="76.0" />
        <line x1="66.7" y1="75.3" x2="72.7" y2="75.3" />
        <line x1="68.6" y1="78.1" x2="70.8" y2="72.5" />
      </g>
    </svg>
  );
}
