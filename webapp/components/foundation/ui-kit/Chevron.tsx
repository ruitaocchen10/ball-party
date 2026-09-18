/**
 * The one "this expands" affordance in the app — a real stroked chevron
 * rather than the ▸/▾ glyphs this used to be. Those sit tiny and off-center
 * inside their own character box no matter how large the font-size gets, so
 * bumping the text size around them barely moved the needle; an actual
 * sized SVG scales the way a reader expects an icon to.
 *
 * Shared by every disclosure in the app (sabotage draft's roster board, the
 * final standings screen's per-user roster) rather than redefined per
 * caller — one icon, one rotation contract (see the comment on its `path`
 * below), used everywhere something expands.
 */
export function Chevron({ className = "" }: { className?: string }) {
  // Points right at rest, matching the old ▸ glyph this replaced — a caller
  // that wants it resting some other way rotates it itself. Deliberately
  // *not* right-pointing via a Tailwind rotate utility layered on top of a
  // down-pointing base: Tailwind's utilities live in a cascade layer above
  // this file's @layer components rules, so a components-layer override
  // (like an open-state rotate) can never beat a rotate utility on the same
  // element regardless of selector specificity — the layer order settles it
  // first. Baking the resting orientation into the path sidesteps that
  // fight entirely.
  return (
    <svg aria-hidden="true" viewBox="0 0 16 16" fill="none" className={className}>
      <path d="M6 4l4 4-4 4" stroke="currentColor" strokeWidth={2} strokeLinecap="round" strokeLinejoin="round" />
    </svg>
  );
}
