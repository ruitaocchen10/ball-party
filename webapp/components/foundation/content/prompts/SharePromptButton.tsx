"use client";

import { Share2 } from "lucide-react";
import { useRef } from "react";

import { Button } from "@/components/foundation/ui-kit/Button";
import { SharePromptCard } from "./SharePromptCard";
import { SharePreviewModal } from "./SharePreviewModal";
import { useShareImage } from "./useShareImage";
import { COVER_OPTION_LIMIT, coverOptions, needsCoverChoice } from "@/lib/foundation/content/prompts/logic";
import type { Option } from "@/lib/foundation/content/prompts/types";

const DEFAULT_SUBHEADLINE = "Pick one";
const MIN_CANDIDATES = 2;

/**
 * The admin's "make an Instagram image of this prompt" action for a pick-one
 * prompt. Renders the question and its candidates — no answers — off-screen,
 * rasterizes it on demand, and previews it before download; see useShareImage.
 * The image shows the prompt's art candidates — up to four, the admin's choice
 * for a bigger pool — so it waits for that choice rather than guess.
 */
export function SharePromptButton({ promptText, options }: { promptText: string; options: Option[] }) {
  const cardRef = useRef<HTMLDivElement>(null);
  const share = useShareImage({ cardRef, defaultHeadline: promptText, defaultSubheadline: DEFAULT_SUBHEADLINE });
  const hint = options.length < MIN_CANDIDATES
    ? `Choose at least ${MIN_CANDIDATES} candidates to make a share image`
    : needsCoverChoice(options)
      ? `Choose ${COVER_OPTION_LIMIT} players for the prompt art to make a share image`
      : null;

  return (
    <>
      <Button
        type="button"
        variant="ghost"
        fullWidth
        disabled={hint !== null || share.phase === "rendering"}
        onClick={() => void share.generate()}
        aria-label="Preview a shareable image of this prompt"
      >
        <span className="inline-flex items-center justify-center gap-2">
          <Share2 className="h-4 w-4" strokeWidth={2.2} />
          {share.phase === "rendering" ? "Making image…" : "Share image"}
        </span>
      </Button>
      {hint ? <p className="mt-1.5 text-center font-mono text-[9px] tracking-[0.1em] text-fg-muted uppercase">{hint}</p> : null}

      {share.phase === "rendering" ? (
        <div style={{ position: "fixed", top: 0, left: -9999, pointerEvents: "none" }} aria-hidden>
          <SharePromptCard ref={cardRef} options={coverOptions(options)} headline={share.headline} subheadline={share.subheadline} format={share.format} />
        </div>
      ) : null}

      {share.phase === "preview" && share.dataUrl ? (
        <SharePreviewModal
          imageUrl={share.dataUrl}
          imageAlt="Preview of your shareable prompt graphic"
          headline={share.headline}
          defaultHeadline={promptText}
          headlineMaxLength={80}
          subheadline={share.subheadline}
          defaultSubheadline={DEFAULT_SUBHEADLINE}
          previewIsCurrent={share.previewIsCurrent}
          onHeadlineChange={share.setHeadline}
          onResetHeadline={share.resetHeadline}
          onSubheadlineChange={share.setSubheadline}
          onResetSubheadline={share.resetSubheadline}
          format={share.format}
          showFormat
          onFormatChange={share.changeFormat}
          onUpdate={() => void share.generate()}
          onDownload={() => share.download(`ball-party-prompt-${share.format}.png`)}
          onClose={share.close}
        />
      ) : null}

      {share.phase === "error" ? (
        <SharePreviewModal error onRetry={() => void share.generate()} onClose={share.close} />
      ) : null}
    </>
  );
}
