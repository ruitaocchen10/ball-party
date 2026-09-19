import { Check, X } from "lucide-react";
import { forwardRef } from "react";

import { PromptTeamLogo } from "./PromptTeamLogo";
import { teamPrimaryColor } from "@/lib/foundation/content/nfl/team-logos";
import { isSlotGraded } from "@/lib/foundation/content/prompts/logic";
import type { Option, Post, Slot } from "@/lib/foundation/content/prompts/types";

const CARD_WIDTH = 540; // doubled on export (see ShareTakeButton's pixelRatio) for a 1080px-wide PNG.
const CARD_HEIGHT = 675; // 4:5 at the 540px working size; exported at 1080 × 1350.
const ticketClip = "polygon(24px 0, 100% 0, 100% calc(100% - 14px), calc(100% - 24px) 100%, 0 100%, 0 14px)";

/**
 * The downloadable "my picks" graphic (ShareTakeButton renders this off-screen
 * and rasterizes it). Deliberately built from fixed pixel values rather than
 * the app's own responsive Tailwind classes: MatchupPicker's `sm:` tiles key
 * off the browser viewport, not this card's own box, so reusing them here
 * would make the export's layout depend on the visitor's window width.
 */
export const SharePicksCard = forwardRef<
  HTMLDivElement,
  {
    post: Post;
    responses: Record<string, string[]>;
    headline?: string;
    subheadline?: string;
  }
>(function SharePicksCard({ post, responses, headline = post.templateName, subheadline = "My picks" }, ref) {
  const matchupSlots = post.slots.filter((slot) => slot.options.length === 2 && slot.options.every((option) => option.teamCode));
  const single = matchupSlots.length === 1;
  const compactRows = Math.ceil(matchupSlots.length / 2);
  const compactGap = compactRows > 5 ? 4 : compactRows > 3 ? 7 : 10;

  return (
    <div
      ref={ref}
      style={{ width: CARD_WIDTH, height: CARD_HEIGHT, fontFamily: "var(--font-sans)" }}
      className="relative flex flex-col overflow-hidden bg-surface text-fg"
    >
      <div
        aria-hidden
        className="pointer-events-none absolute inset-0"
        style={{
          backgroundImage: [
            "linear-gradient(143deg, rgb(112 114 106 / 0.46) 0%, rgb(69 72 67 / 0.34) 21%, transparent 21.3%)",
            "linear-gradient(323deg, rgb(74 77 72 / 0.58) 0%, rgb(35 38 35 / 0.44) 29%, transparent 29.3%)",
            "radial-gradient(58% 31% at 50% 19%, rgb(201 56 44 / 0.3), transparent 72%)",
            "radial-gradient(circle at center, rgb(232 227 214 / 0.07) 0.75px, transparent 1px)",
            "linear-gradient(162deg, transparent 0%, transparent 52%, rgb(232 227 214 / 0.2) 52.15%, rgb(232 227 214 / 0.2) 52.4%, transparent 52.55%)",
            "linear-gradient(160deg, #1a1e1a 0%, #101310 54%, #080a08 100%)",
          ].join(", "),
          backgroundSize: "auto, auto, auto, 9px 9px, auto, auto",
        }}
      />

      <header className="relative z-10 flex h-[128px] shrink-0 flex-col items-center gap-1 px-8 pt-10 text-center">
        <p className="max-w-full overflow-hidden font-mono text-xs leading-none font-semibold tracking-[0.18em] text-[#c9382c] text-ellipsis whitespace-nowrap uppercase">{subheadline}</p>
        <h1 className="max-w-full overflow-hidden font-slab text-[66px] leading-[0.95] text-ellipsis whitespace-nowrap uppercase text-fg">{headline}</h1>
      </header>

      <div className={`relative z-10 mt-4 min-h-0 flex-1 px-6 pb-6 ${single ? "flex flex-col px-8" : ""}`}>
        {single ? (
          <ShareFeaturedMatchup slot={matchupSlots[0]} response={responses[matchupSlots[0].id] ?? []} />
        ) : (
          <div className="grid h-full grid-cols-2" style={{ gap: compactGap, gridTemplateRows: `repeat(${compactRows}, minmax(0, 1fr))` }}>
            {matchupSlots.map((slot) => (
              <ShareCompactMatchup key={slot.id} slot={slot} response={responses[slot.id] ?? []} rows={compactRows} />
            ))}
          </div>
        )}
      </div>
    </div>
  );
});

function ShareFeaturedMatchup({ slot, response }: { slot: Slot; response: string[] }) {
  const [away, home] = slot.options;
  const pickedId = response[0] ?? null;
  const graded = isSlotGraded(slot);
  return (
    <div className="h-full w-full overflow-hidden border border-line bg-surface-raised" style={{ clipPath: ticketClip }}>
      <div className="relative flex h-full flex-col">
        {pickedId === away.id ? <div aria-hidden className="absolute inset-y-0 left-0 w-1/2" style={surface(away)} /> : null}
        {pickedId === home.id ? <div aria-hidden className="absolute inset-y-0 right-0 w-1/2" style={surface(home)} /> : null}
        <div className="relative z-10 flex items-center justify-between px-5 pt-5 font-mono text-[10px] font-semibold tracking-[0.16em] text-fg/70 uppercase">
          <span className={pickedId === away.id ? "text-panel/80" : ""}>Your call</span>
          <span className={pickedId === home.id ? "text-panel/80" : ""}>Pick the winner</span>
        </div>
        <div aria-hidden className="absolute top-11 bottom-0 left-1/2 z-10 w-px bg-fg/20" />
        <div className="relative z-10 grid min-h-0 flex-1 grid-cols-[minmax(0,1fr)_auto_minmax(0,1fr)] items-stretch gap-5 px-5 py-3">
          <ShareFeaturedSide option={away} picked={pickedId === away.id} graded={graded} correct={graded && pickedId === slot.correct?.[0] && pickedId === away.id} />
          <span aria-hidden className="flex h-11 w-11 self-center items-center justify-center rounded-full border border-fg/30 bg-transparent font-mono text-sm font-bold text-fg shadow-[0_4px_12px_rgb(0_0_0/0.25)]">@</span>
          <ShareFeaturedSide option={home} picked={pickedId === home.id} graded={graded} correct={graded && pickedId === slot.correct?.[0] && pickedId === home.id} />
        </div>
        <div className="relative mx-5 flex justify-center border-t border-fg/20 pt-3 pb-5 font-mono text-[10px] tracking-[0.14em] text-fg/70 uppercase">{slot.label}</div>
      </div>
    </div>
  );
}

function ShareFeaturedSide({ option, picked, graded, correct }: { option: Option; picked: boolean; graded: boolean; correct: boolean }) {
  const style = picked && option.teamCode ? { color: "#fffdf7" } : undefined;
  return (
    <div style={style} className="relative flex h-full min-w-0 flex-col items-center justify-center gap-3 px-3 py-3 text-center">
      {option.teamCode ? (
        <PromptTeamLogo code={option.teamCode} className={`h-44 w-44 drop-shadow-[0_10px_16px_rgb(0_0_0/0.4)] ${picked ? "" : "opacity-40 grayscale"}`} />
      ) : null}
      <span className="font-slab text-2xl leading-none uppercase">{option.label}</span>
      {graded && picked ? (
        <span className="absolute top-3 right-3">{correct ? <Check className="h-6 w-6 text-grade-elite" strokeWidth={3} /> : <X className="h-6 w-6 text-grade-rough" strokeWidth={3} />}</span>
      ) : null}
    </div>
  );
}

function ShareCompactMatchup({ slot, response, rows }: { slot: Slot; response: string[]; rows: number }) {
  const [away, home] = slot.options;
  const pickedId = response[0] ?? null;
  const graded = isSlotGraded(slot);
  const correct = graded && pickedId === slot.correct?.[0];
  return (
    <div className="flex h-full min-h-0 flex-col overflow-hidden border border-line bg-surface-raised" style={{ clipPath: ticketClip }}>
      <div className="relative grid min-h-0 flex-1 grid-cols-2 divide-x divide-line">
        <ShareCompactSide option={away} picked={pickedId === away.id} graded={graded} correct={correct} rows={rows} />
        <ShareCompactSide option={home} picked={pickedId === home.id} graded={graded} correct={correct} rows={rows} />
        <div aria-hidden className="pointer-events-none absolute inset-y-0 left-1/2 z-10 flex -translate-x-1/2 items-center justify-center"><span className="absolute inset-y-3 left-1/2 w-px bg-line" /><span className="relative flex h-8 w-8 items-center justify-center rounded-full border border-line bg-surface font-mono text-xs font-bold text-fg-muted">@</span></div>
      </div>
      <div aria-hidden className="mx-3 h-1 border-t border-line/70" />
    </div>
  );
}

function ShareCompactSide({ option, picked, graded, correct, rows }: { option: Option; picked: boolean; graded: boolean; correct: boolean; rows: number }) {
  const color = option.teamCode ? teamPrimaryColor(option.teamCode) : null;
  const style = picked && color ? surface(option) : undefined;
  // Prioritize the marks: the tile remains readable as a pick at a glance even
  // on a fuller slate. These steps still fit within the fixed 4:5 canvas.
  const logoSize = rows > 9 ? "h-10 w-10" : rows > 8 ? "h-12 w-12" : rows > 7 ? "h-16 w-16" : rows > 6 ? "h-20 w-20" : rows > 5 ? "h-24 w-24" : rows > 4 ? "h-28 w-28" : rows > 3 ? "h-[7.5rem] w-[7.5rem]" : rows > 2 ? "h-32 w-32" : "h-32 w-32";
  return (
    <div style={style} className={`relative flex h-full min-h-0 items-center justify-center overflow-hidden ${picked ? "" : "bg-surface/85"}`}>
      {option.teamCode ? <PromptTeamLogo code={option.teamCode} className={`${logoSize} ${picked ? "" : "opacity-40 grayscale"}`} /> : null}
      <span className="sr-only">{option.label}</span>
      {graded && picked ? (
        <span className="absolute top-1 right-1">{correct ? <Check className="h-3.5 w-3.5 text-grade-elite" strokeWidth={3} /> : <X className="h-3.5 w-3.5 text-grade-rough" strokeWidth={3} />}</span>
      ) : null}
    </div>
  );
}

function surface(option: Option) {
  const color = option.teamCode ? teamPrimaryColor(option.teamCode) : null;
  return color ? { background: `linear-gradient(135deg, ${color}, #111311)` } : undefined;
}
