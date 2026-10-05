import { CandidateTile, type TileMetrics } from "./CandidateTile";
import type { Option } from "@/lib/foundation/content/prompts/types";

/**
 * Tile height and sizing by how many candidates the art shows. The tiles share
 * the card's width, so the more there are the narrower each is: a four-across
 * tile is only about 80px wide on a phone, which is why it drops the first name
 * and takes a smaller cut. Portrait sizes are a share of the tile so the face
 * stays in proportion at any card width.
 */
const FEED_TILES: Record<number, { height: number; metrics: TileMetrics }> = {
  1: { height: 260, metrics: { portraitHeight: "86%", headshotRequestWidth: 700, logoClass: "w-[60%]", lastNameSize: 28, firstNameClass: "text-[13px]", plateClass: "px-3 pt-14 pb-3", cut: [18, 12] } },
  2: { height: 250, metrics: { portraitHeight: "84%", headshotRequestWidth: 640, logoClass: "w-[72%]", lastNameSize: 26, firstNameClass: "text-[12px]", plateClass: "px-2 pt-12 pb-3", cut: [16, 11] } },
  3: { height: 220, metrics: { portraitHeight: "80%", headshotRequestWidth: 520, logoClass: "w-[78%]", lastNameSize: 20, firstNameClass: "text-[10px]", plateClass: "px-1.5 pt-10 pb-2.5", cut: [14, 10] } },
  4: { height: 200, metrics: { portraitHeight: "76%", headshotRequestWidth: 440, logoClass: "w-[82%]", lastNameSize: 15, firstNameClass: "text-[9px]", plateClass: "px-1 pt-8 pb-2", showFirstName: false, cut: [12, 8] } },
};

/**
 * The art on a pick-one prompt's feed card: the candidates side by side, up to
 * four. A pool bigger than the art says how many aren't shown — everyone can
 * still answer with any of them.
 */
export function PickOneBoard({ options, poolSize }: { options: Option[]; poolSize: number }) {
  const shown = options.slice(0, 4);
  const { height, metrics } = FEED_TILES[Math.max(shown.length, 1)];
  const hidden = poolSize - shown.length;

  return (
    <section data-testid="pick-one-board" aria-label="Candidates" className="mx-4 mt-4">
      <div className="flex gap-2">
        {shown.map((option) => (
          <div key={option.id} className="min-w-0 flex-1" style={{ height }}>
            <CandidateTile option={option} metrics={metrics} className="h-full" />
          </div>
        ))}
      </div>
      {hidden > 0 ? (
        <p className="mt-2 text-center type-label text-fg-muted">+{hidden} more to choose from</p>
      ) : null}
    </section>
  );
}
