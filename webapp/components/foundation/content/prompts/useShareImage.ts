"use client";

import { toPng } from "html-to-image";
import { useState, type RefObject } from "react";

import type { ShareFormat } from "./shareFormat";

export type SharePhase = "idle" | "rendering" | "preview" | "error";

/**
 * The generate-then-preview flow behind every downloadable share graphic.
 * The card mounts off-screen only while `phase` is "rendering" and is read
 * through the caller's `cardRef`; the result is shown in a preview before anything reaches
 * disk — html-to-image's rendering of a fresh DOM tree can surprise you (a
 * logo that failed to load, unlucky wrapping), so a raw click-to-download
 * would let the first look at a bad image be the download itself.
 */
export function useShareImage({
  cardRef,
  defaultHeadline,
  defaultSubheadline,
}: {
  /** Attached by the caller to the off-screen card that gets rasterized. */
  cardRef: RefObject<HTMLDivElement | null>;
  defaultHeadline: string;
  defaultSubheadline: string;
}) {
  const [phase, setPhase] = useState<SharePhase>("idle");
  const [dataUrl, setDataUrl] = useState<string | null>(null);
  // An edit in the preview modal overrides the default; with none, the text keeps
  // following its default (the admin composer's prompt text is edited live).
  const [headlineOverride, setHeadline] = useState<string | null>(null);
  const [subheadlineOverride, setSubheadline] = useState<string | null>(null);
  const headline = headlineOverride ?? defaultHeadline;
  const subheadline = subheadlineOverride ?? defaultSubheadline;
  const [format, setFormat] = useState<ShareFormat>("post");
  // What the current preview was drawn from, so an edit can be flagged as not yet rendered.
  const [rendered, setRendered] = useState<{ headline: string; subheadline: string; format: ShareFormat } | null>(null);

  async function generate(selectedFormat: ShareFormat = format) {
    setPhase("rendering");
    // The off-screen card only mounts on this click, so give it a paint
    // before html-to-image reads its layout.
    await new Promise((resolve) => requestAnimationFrame(() => requestAnimationFrame(resolve)));
    try {
      const node = cardRef.current;
      if (!node) throw new Error("Card not ready");
      const png = await toPng(node, { pixelRatio: 2, cacheBust: true, backgroundColor: "#111311" });
      setDataUrl(png);
      setRendered({ headline, subheadline, format: selectedFormat });
      setPhase("preview");
    } catch {
      setPhase("error");
    }
  }

  function changeFormat(nextFormat: ShareFormat) {
    if (nextFormat === format) return;
    setFormat(nextFormat);
    // Format is a structural change, not merely preview metadata. Rebuild at
    // once so the image the person sees always matches their selection.
    void generate(nextFormat);
  }

  function download(filename: string) {
    if (!dataUrl) return;
    const link = document.createElement("a");
    link.download = filename;
    link.href = dataUrl;
    link.click();
  }

  function close() {
    setPhase("idle");
    setDataUrl(null);
    setRendered(null);
  }

  return {
    phase,
    dataUrl,
    headline,
    setHeadline,
    resetHeadline: () => setHeadline(null),
    subheadline,
    setSubheadline,
    resetSubheadline: () => setSubheadline(null),
    format,
    previewIsCurrent: rendered !== null && rendered.headline === headline && rendered.subheadline === subheadline && rendered.format === format,
    generate,
    changeFormat,
    download,
    close,
  };
}
