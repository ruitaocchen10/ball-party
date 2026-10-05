import { PromptTeamLogo } from "./PromptTeamLogo";
import { resizedHeadshotUrl } from "@/lib/foundation/content/nfl/headshots";
import { teamPrimaryColor } from "@/lib/foundation/content/nfl/team-logos";
import type { Option } from "@/lib/foundation/content/prompts/types";

/** NFL.com headshots are all 3400 × 2450 — head and shoulders on a transparent background. */
const HEADSHOT_ASPECT = "3400 / 2450";

/**
 * How one candidate tile is sized. The same tile is drawn at two scales — the
 * fixed 540px Instagram card and the responsive feed row — so everything that
 * depends on scale is in here rather than in the tile.
 */
export type TileMetrics = {
  /**
   * CSS height of the headshot box, anchored to the tile's bottom: pixels on
   * the fixed share card, a percentage of the tile in the feed. Its width
   * follows the photo's aspect and the tile crops it, so the face stays
   * centered whatever the tile's width.
   */
  portraitHeight: string;
  /** Width requested from the image CDN: the box's width at the export's 2×, so the image stays sharp without pulling the multi-MB original. */
  headshotRequestWidth: number;
  logoClass: string;
  lastNameSize: number;
  firstNameClass: string;
  plateClass: string;
  /** A narrow tile shows the surname alone. */
  showFirstName?: boolean;
  /** How far the ticket's cut corners bite in, horizontally and vertically, in px. */
  cut?: [horizontal: number, vertical: number];
};

/**
 * A candidate in a pick-one prompt's art: a team-colour ticket with a faint
 * team-logo watermark, the player's face, and a name plate with the surname as
 * the big line. A player with no headshot gets initials.
 */
export function CandidateTile({ option, metrics, className = "" }: { option: Option; metrics: TileMetrics; className?: string }) {
  const { first, last } = splitName(option.label);
  const teamColor = option.teamCode ? teamPrimaryColor(option.teamCode) : null;
  const lastNameSize = last.length > 11 ? metrics.lastNameSize * 0.72 : last.length > 8 ? metrics.lastNameSize * 0.86 : metrics.lastNameSize;
  const [cutX, cutY] = metrics.cut ?? [20, 14];
  return (
    <div
      style={{
        clipPath: `polygon(${cutX}px 0, 100% 0, 100% calc(100% - ${cutY}px), calc(100% - ${cutX}px) 100%, 0 100%, 0 ${cutY}px)`,
        background: `linear-gradient(135deg, ${teamColor ?? "#30332e"}, #151714 72%)`,
      }}
      className={`relative min-w-0 overflow-hidden border border-white/25 shadow-[0_5px_12px_rgb(0_0_0/0.35)] ${className}`}
    >
      {option.teamCode ? (
        <span aria-hidden className="absolute inset-x-0 top-3 flex justify-center opacity-25">
          <PromptTeamLogo code={option.teamCode} className={metrics.logoClass} />
        </span>
      ) : null}

      {option.headshotUrl ? (
        <span
          aria-hidden
          className="absolute bottom-0 left-1/2 -translate-x-1/2"
          style={{ height: metrics.portraitHeight, aspectRatio: HEADSHOT_ASPECT }}
        >
          {/* eslint-disable-next-line @next/next/no-img-element -- rasterized by html-to-image, which reads the DOM <img>; next/image's optimizer URL would break the export */}
          <img src={resizedHeadshotUrl(option.headshotUrl, metrics.headshotRequestWidth)} alt="" className="h-full w-full object-cover object-top drop-shadow-[0_8px_14px_rgb(0_0_0/0.45)]" />
        </span>
      ) : (
        <span aria-hidden className="absolute inset-x-0 bottom-1/4 flex justify-center font-slab text-[72px] leading-none text-white/35">{initials(option.label)}</span>
      )}

      <div
        className={`absolute inset-x-0 bottom-0 flex flex-col items-center text-center ${metrics.plateClass}`}
        style={{ background: "linear-gradient(to top, rgb(8 10 8 / 0.94) 0%, rgb(8 10 8 / 0.78) 58%, transparent 100%)" }}
      >
        {first && metrics.showFirstName !== false ? <span className={`max-w-full overflow-hidden font-slab leading-none text-ellipsis whitespace-nowrap text-white/80 uppercase ${metrics.firstNameClass}`}>{first}</span> : null}
        <span className="max-w-full overflow-hidden font-slab leading-[1.05] text-ellipsis whitespace-nowrap uppercase" style={{ fontSize: lastNameSize }}>{last}</span>
        {option.sublabel ? <span className="mt-1 type-label font-semibold text-white/60">{option.sublabel}</span> : null}
      </div>
    </div>
  );
}

/** "Amon-Ra St. Brown" → first "Amon-Ra", last "St. Brown". A single word is all last name. */
function splitName(label: string): { first: string; last: string } {
  const [first, ...rest] = label.trim().split(/\s+/);
  return rest.length ? { first, last: rest.join(" ") } : { first: "", last: first ?? "" };
}

function initials(name: string): string {
  return name.trim().split(/\s+/).filter(Boolean).slice(0, 2).map((part) => part[0]?.toUpperCase()).join("") || "?";
}
