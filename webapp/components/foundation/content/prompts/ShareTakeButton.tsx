"use client";

import { Share2 } from "lucide-react";
import { useRef } from "react";

import { SharePicksCard } from "./SharePicksCard";
import { SharePowerRankingsCard } from "./SharePowerRankingsCard";
import { SharePreviewModal } from "./SharePreviewModal";
import { useShareImage } from "./useShareImage";
import type { Post } from "@/lib/foundation/content/prompts/types";

/**
 * A floating "share my picks" action that appears once a take is locked in.
 * Renders SharePicksCard off-screen, rasterizes it on demand, and shows the
 * result before anything reaches disk — see useShareImage.
 */
export function ShareTakeButton({
  post,
  responses,
}: {
  post: Post;
  responses: Record<string, string[]>;
}) {
  const isPowerRankings = post.templateKind === "power_rankings";
  const shareLabel = isPowerRankings ? "rankings" : "picks";
  const defaultSubheadline = isPowerRankings ? "My power rankings" : "My picks";
  const cardRef = useRef<HTMLDivElement>(null);
  const share = useShareImage({ cardRef, defaultHeadline: post.templateName, defaultSubheadline });

  return (
    <>
      <div className="fixed right-5 bottom-5 z-40">
        <button
          type="button"
          onClick={() => void share.generate()}
          disabled={share.phase === "rendering"}
          aria-label={`Preview a shareable image of your ${shareLabel}`}
          className="flex items-center gap-2 bg-panel px-4 py-3 font-slab text-sm tracking-[0.04em] text-panel-fg uppercase shadow-[0_10px_24px_rgb(0_0_0/0.45)] transition-colors hover:bg-panel-hover disabled:cursor-not-allowed disabled:opacity-60"
        >
          <Share2 className="h-4 w-4" strokeWidth={2.2} />
          {share.phase === "rendering" ? "Making image…" : `Share ${shareLabel}`}
        </button>
      </div>

      {share.phase === "rendering" ? (
        <div style={{ position: "fixed", top: 0, left: -9999, pointerEvents: "none" }} aria-hidden>
          {isPowerRankings ? (
            <SharePowerRankingsCard ref={cardRef} post={post} responses={responses} headline={share.headline} subheadline={share.subheadline} format={share.format} />
          ) : (
            <SharePicksCard ref={cardRef} post={post} responses={responses} headline={share.headline} subheadline={share.subheadline} />
          )}
        </div>
      ) : null}

      {share.phase === "preview" && share.dataUrl ? (
        <SharePreviewModal
          imageUrl={share.dataUrl}
          imageAlt="Preview of your shareable picks graphic"
          headline={share.headline}
          defaultHeadline={post.templateName}
          subheadline={share.subheadline}
          defaultSubheadline={defaultSubheadline}
          previewIsCurrent={share.previewIsCurrent}
          onHeadlineChange={share.setHeadline}
          onResetHeadline={share.resetHeadline}
          onSubheadlineChange={share.setSubheadline}
          onResetSubheadline={share.resetSubheadline}
          format={share.format}
          showFormat={isPowerRankings}
          onFormatChange={share.changeFormat}
          onUpdate={() => void share.generate()}
          onDownload={() => share.download(`ball-party-${post.id}-${shareLabel}-${isPowerRankings ? share.format : "post"}.png`)}
          onClose={share.close}
        />
      ) : null}

      {share.phase === "error" ? (
        <SharePreviewModal error onRetry={() => void share.generate()} onClose={share.close} />
      ) : null}
    </>
  );
}
