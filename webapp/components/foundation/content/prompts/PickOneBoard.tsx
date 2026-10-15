import { Badge } from "@/components/foundation/ui-kit/Badge";
import { CandidateTile, type TileMetrics } from "./CandidateTile";
import { PROMPT_ART_HEIGHT } from "./PromptCover";
import type { Option } from "@/lib/foundation/content/prompts/types";

/**
 * Tile sizing by how many candidates the art shows. The tiles split the card's
 * width, so the more there are the narrower each is: a four-across tile is only
 * about 85px wide on a phone, which is why it drops the first name. The tile
 * fills the banner's height; portrait sizes are a share of the tile so the face
 * stays in proportion at any card width.
 */
const FEED_TILES: Record<number, TileMetrics> = {
  1: { portraitHeight: "92%", headshotRequestWidth: 700, logoClass: "w-[28%]", lastNameSize: 26, firstNameClass: "text-[12px]", plateClass: "px-3 pt-8 pb-2", cut: [0, 0] },
  2: { portraitHeight: "90%", headshotRequestWidth: 640, logoClass: "w-[40%]", lastNameSize: 24, firstNameClass: "text-[11px]", plateClass: "px-2 pt-8 pb-2", cut: [0, 0] },
  3: { portraitHeight: "88%", headshotRequestWidth: 520, logoClass: "w-[52%]", lastNameSize: 19, firstNameClass: "text-[10px]", plateClass: "px-1.5 pt-7 pb-1.5", cut: [0, 0] },
  4: { portraitHeight: "86%", headshotRequestWidth: 440, logoClass: "w-[60%]", lastNameSize: 15, firstNameClass: "text-[9px]", plateClass: "px-1 pt-6 pb-1.5", showFirstName: false, cut: [0, 0] },
};

/**
 * The art on a pick-one prompt's feed card: the candidates side by side, up to
 * four, as one banner. A pool bigger than the art says how many aren't shown in
 * the corner, since everyone can still answer with any of them.
 */
export function PickOneBoard({ options, poolSize }: { options: Option[]; poolSize: number }) {
  const shown = options.slice(0, 4);
  const metrics = FEED_TILES[Math.max(shown.length, 1)];
  const hidden = poolSize - shown.length;

  return (
    <section data-testid="pick-one-board" aria-label="Candidates" className={`relative overflow-hidden ${PROMPT_ART_HEIGHT}`}>
      <div className="flex h-full gap-px bg-line">
        {shown.map((option) => (
          <div key={option.id} className="min-w-0 flex-1">
            <CandidateTile option={option} metrics={metrics} className="h-full" />
          </div>
        ))}
      </div>
      {hidden > 0 ? (
        <Badge tone="scrim" size="xs" className="absolute bottom-2 left-2 z-10">+{hidden} more to choose from</Badge>
      ) : null}
    </section>
  );
}
