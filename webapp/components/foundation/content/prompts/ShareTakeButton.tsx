"use client";

import { toPng } from "html-to-image";
import { Download, Share2, X } from "lucide-react";
import { useEffect, useRef, useState } from "react";

import { SharePicksCard } from "./SharePicksCard";
import type { Post } from "@/lib/foundation/content/prompts/types";

type Phase = "idle" | "rendering" | "preview" | "error";

/**
 * A floating "share my picks" action that appears once a take is locked in.
 * Renders SharePicksCard off-screen, rasterizes it on demand, and shows the
 * result before anything reaches disk — html-to-image's rendering of a fresh
 * DOM tree can surprise you (a logo that failed to load, unlucky wrapping),
 * so a raw click-to-download would let the first look at a bad image be the
 * download itself.
 */
export function ShareTakeButton({
  post,
  responses,
  resolved,
}: {
  post: Post;
  responses: Record<string, string[]>;
  resolved: boolean;
}) {
  const cardRef = useRef<HTMLDivElement>(null);
  const [phase, setPhase] = useState<Phase>("idle");
  const [dataUrl, setDataUrl] = useState<string | null>(null);
  const [headline, setHeadline] = useState(post.templateName);
  const [subheadline, setSubheadline] = useState("My picks");
  const [renderedHeadline, setRenderedHeadline] = useState<string | null>(null);
  const [renderedSubheadline, setRenderedSubheadline] = useState<string | null>(null);

  async function handleGenerate() {
    setPhase("rendering");
    // The off-screen card only mounts on this click, so give it a paint
    // before html-to-image reads its layout.
    await new Promise((resolve) => requestAnimationFrame(() => requestAnimationFrame(resolve)));
    try {
      const node = cardRef.current;
      if (!node) throw new Error("Card not ready");
      const png = await toPng(node, { pixelRatio: 2, cacheBust: true, backgroundColor: "#111311" });
      setDataUrl(png);
      setRenderedHeadline(headline);
      setRenderedSubheadline(subheadline);
      setPhase("preview");
    } catch {
      setPhase("error");
    }
  }

  function handleDownload() {
    if (!dataUrl) return;
    const link = document.createElement("a");
    link.download = `ball-party-${post.id}-picks.png`;
    link.href = dataUrl;
    link.click();
  }

  function handleClose() {
    setPhase("idle");
    setDataUrl(null);
    setRenderedHeadline(null);
    setRenderedSubheadline(null);
  }

  return (
    <>
      <div className="fixed right-5 bottom-5 z-40">
        <button
          type="button"
          onClick={handleGenerate}
          disabled={phase === "rendering"}
          aria-label="Preview a shareable image of your picks"
          className="flex items-center gap-2 bg-panel px-4 py-3 font-slab text-sm tracking-[0.04em] text-panel-fg uppercase shadow-[0_10px_24px_rgb(0_0_0/0.45)] transition-colors hover:bg-[#fffdf7] disabled:cursor-not-allowed disabled:opacity-60"
        >
          <Share2 className="h-4 w-4" strokeWidth={2.2} />
          {phase === "rendering" ? "Making image…" : "Share picks"}
        </button>
      </div>

      {phase === "rendering" ? (
        <div style={{ position: "fixed", top: 0, left: -9999, pointerEvents: "none" }} aria-hidden>
          <SharePicksCard ref={cardRef} post={post} responses={responses} resolved={resolved} headline={headline} subheadline={subheadline} />
        </div>
      ) : null}

      {phase === "preview" && dataUrl ? (
          <SharePreviewModal
            imageUrl={dataUrl}
            headline={headline}
            defaultHeadline={post.templateName}
            subheadline={subheadline}
            defaultSubheadline="My picks"
            previewIsCurrent={headline === renderedHeadline && subheadline === renderedSubheadline}
            onHeadlineChange={setHeadline}
            onResetHeadline={() => setHeadline(post.templateName)}
            onSubheadlineChange={setSubheadline}
            onResetSubheadline={() => setSubheadline("My picks")}
            onUpdate={handleGenerate}
            onDownload={handleDownload}
            onClose={handleClose}
          />
      ) : null}

      {phase === "error" ? (
        <SharePreviewModal error onRetry={handleGenerate} onClose={handleClose} />
      ) : null}
    </>
  );
}

function SharePreviewModal({
  imageUrl,
  error = false,
  headline,
  defaultHeadline,
  subheadline,
  defaultSubheadline,
  previewIsCurrent,
  onHeadlineChange,
  onResetHeadline,
  onSubheadlineChange,
  onResetSubheadline,
  onUpdate,
  onDownload,
  onRetry,
  onClose,
}: {
  imageUrl?: string;
  error?: boolean;
  headline?: string;
  defaultHeadline?: string;
  subheadline?: string;
  defaultSubheadline?: string;
  previewIsCurrent?: boolean;
  onHeadlineChange?: (headline: string) => void;
  onResetHeadline?: () => void;
  onSubheadlineChange?: (subheadline: string) => void;
  onResetSubheadline?: () => void;
  onUpdate?: () => void;
  onDownload?: () => void;
  onRetry?: () => void;
  onClose: () => void;
}) {
  useEffect(() => {
    function onKeyDown(event: KeyboardEvent) {
      if (event.key === "Escape") onClose();
    }
    document.addEventListener("keydown", onKeyDown);
    const { overflow } = document.body.style;
    document.body.style.overflow = "hidden";
    return () => {
      document.removeEventListener("keydown", onKeyDown);
      document.body.style.overflow = overflow;
    };
  }, [onClose]);

  return (
    <div className="fixed inset-0 z-50 flex items-center justify-center p-4" role="presentation">
      <button type="button" aria-label="Close preview" onClick={onClose} className="absolute inset-0 bg-black/70" />
      <section role="dialog" aria-modal="true" aria-labelledby="share-preview-title" className="relative flex max-h-[90vh] w-full max-w-sm flex-col bg-surface-raised shadow-card">
        <div className="flex items-center justify-between border-b border-line px-4 py-3">
          <p id="share-preview-title" className="font-mono text-xs font-semibold tracking-[0.13em] text-fg-muted uppercase">
            {error ? "Couldn't make image" : "Preview"}
          </p>
          <button type="button" onClick={onClose} aria-label="Close preview" className="flex h-8 w-8 items-center justify-center text-fg-muted hover:text-fg focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-panel">
            <X className="h-4 w-4" strokeWidth={1.8} />
          </button>
        </div>

        {error ? (
          <div className="px-4 py-8 text-center">
            <p className="text-sm text-fg-muted">Something went wrong putting the graphic together.</p>
          </div>
        ) : (
          <div className="min-h-0 flex-1 overflow-y-auto bg-surface p-3">
            {/* eslint-disable-next-line @next/next/no-img-element -- a rasterized data URI, not an app asset next/image can optimize */}
            <img src={imageUrl} alt="Preview of your shareable picks graphic" className="w-full" />
          </div>
        )}

        {!error ? (
          <div className="flex flex-col gap-3 border-t border-line px-4 py-3">
            <ShareHeadlineField id="share-subheadline" label="Subheadline" value={subheadline} defaultValue={defaultSubheadline} maxLength={28} onChange={onSubheadlineChange} onReset={onResetSubheadline} red />
            <ShareHeadlineField id="share-headline" label="Headline" value={headline} defaultValue={defaultHeadline} maxLength={40} onChange={onHeadlineChange} onReset={onResetHeadline} />
          </div>
        ) : null}

        <div className="flex items-center gap-3 border-t border-line px-4 py-3">
          {error ? (
            <button type="button" onClick={onRetry} className="bg-panel px-3.5 py-2.5 font-mono text-xs font-bold tracking-[0.13em] text-panel-fg uppercase">
              Try again
            </button>
          ) : (
            <>
              <button type="button" onClick={onUpdate} disabled={previewIsCurrent} className="bg-surface-raised px-3.5 py-2.5 font-mono text-xs font-bold tracking-[0.13em] text-fg uppercase disabled:hidden">Update preview</button>
              <button type="button" onClick={onDownload} disabled={!previewIsCurrent} className="flex items-center gap-2 bg-panel px-3.5 py-2.5 font-mono text-xs font-bold tracking-[0.13em] text-panel-fg uppercase disabled:cursor-not-allowed disabled:opacity-50">
                <Download className="h-3.5 w-3.5" strokeWidth={2.2} /> Download
              </button>
            </>
          )}
          <button type="button" onClick={onClose} className="font-mono text-xs tracking-[0.1em] text-fg-muted uppercase hover:text-fg">
            {error ? "Dismiss" : "Cancel"}
          </button>
        </div>
      </section>
    </div>
  );
}

function ShareHeadlineField({ id, label, value, defaultValue, maxLength, onChange, onReset, red = false }: { id: string; label: string; value?: string; defaultValue?: string; maxLength: number; onChange?: (value: string) => void; onReset?: () => void; red?: boolean }) {
  return (
    <div>
      <label htmlFor={id} className="mb-1.5 block font-mono text-[10px] font-semibold tracking-[0.12em] text-fg-muted uppercase">{label}</label>
      <div className="flex gap-2">
        <input id={id} value={value} maxLength={maxLength} onChange={(event) => onChange?.(event.target.value)} className={`min-w-0 flex-1 border border-line bg-surface px-2.5 py-2 ${red ? "font-mono text-xs font-semibold tracking-[0.12em] text-[#c9382c]" : "font-slab text-sm text-fg"} uppercase outline-none focus:border-fg-muted`} />
        {value !== defaultValue ? <button type="button" onClick={onReset} className="shrink-0 font-mono text-[10px] tracking-[0.08em] text-fg-muted uppercase hover:text-fg">Reset</button> : null}
      </div>
    </div>
  );
}
