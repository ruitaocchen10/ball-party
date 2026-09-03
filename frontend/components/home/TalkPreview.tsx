import { Concealed } from "@/components/ui/Concealed";

/**
 * The Talk column's only content until prompts are a real feature.
 *
 * Deliberately not a mocked-up prompt card. `GAMES` already draws a hard line
 * between "playable" and "planned" (see lib/games/catalog) because a tile that
 * claims to work when it doesn't is the product lying about itself — the same
 * rule applies here. This reuses the concealed weave `InDevelopment` already
 * spends on games nobody can play yet, sized to roughly match a featured game
 * tile so Play and Talk still read as an even split while one side is empty.
 */
export function TalkPreview() {
  return (
    <Concealed
      label="Social prompts, in development"
      className="flex min-h-[220px] flex-col justify-center gap-2.5 px-5 py-7 sm:px-6"
    >
      <p className="font-mono text-[10px] tracking-[0.16em] text-panel/80 uppercase">
        Coming soon
      </p>
      <p className="font-slab text-xl leading-[1.05] text-panel uppercase sm:text-2xl">
        Social prompts
        <br />
        are in development
      </p>
      <p className="max-w-[38ch] text-[13px] leading-[1.55] text-panel/85">
        A prompt to answer and argue about with your group, every day. This
        column fills in once that&apos;s real — nothing to click here yet.
      </p>
    </Concealed>
  );
}
