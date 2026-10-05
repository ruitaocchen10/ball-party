"use client";

import { Download, X } from "lucide-react";

import { Modal, ModalTitle } from "@/components/foundation/ui-kit/Modal";
import type { ShareFormat } from "./shareFormat";

export function SharePreviewModal({
  imageUrl,
  imageAlt = "Preview of your shareable graphic",
  error = false,
  headline,
  defaultHeadline,
  headlineMaxLength = 40,
  subheadline,
  defaultSubheadline,
  subheadlineMaxLength = 28,
  previewIsCurrent,
  onHeadlineChange,
  onResetHeadline,
  onSubheadlineChange,
  onResetSubheadline,
  onUpdate,
  onDownload,
  onRetry,
  onClose,
  format,
  showFormat,
  onFormatChange,
}: {
  imageUrl?: string;
  imageAlt?: string;
  error?: boolean;
  headline?: string;
  defaultHeadline?: string;
  headlineMaxLength?: number;
  subheadline?: string;
  defaultSubheadline?: string;
  subheadlineMaxLength?: number;
  previewIsCurrent?: boolean;
  onHeadlineChange?: (headline: string) => void;
  onResetHeadline?: () => void;
  onSubheadlineChange?: (subheadline: string) => void;
  onResetSubheadline?: () => void;
  onUpdate?: () => void;
  onDownload?: () => void;
  onRetry?: () => void;
  onClose: () => void;
  format?: ShareFormat;
  showFormat?: boolean;
  onFormatChange?: (format: ShareFormat) => void;
}) {
  return (
    <Modal onClose={onClose} closeLabel="Close preview" size="sm" padded={false} closeButton={false} className="flex max-h-[90vh] flex-col">
      <div className="flex items-center justify-between border-b border-line px-4 py-3">
        <ModalTitle asChild>
          <p className="font-mono text-xs font-semibold tracking-[0.13em] text-fg-muted uppercase">
            {error ? "Couldn't make image" : "Preview"}
          </p>
        </ModalTitle>
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
          <img src={imageUrl} alt={imageAlt} className={showFormat ? "mx-auto max-h-[34vh] w-auto max-w-full" : "w-full"} />
        </div>
      )}

      {!error ? (
        <div className="flex flex-col gap-3 border-t border-line px-4 py-3">
          {showFormat ? <ShareFormatField format={format ?? "post"} onChange={onFormatChange} /> : null}
          <ShareHeadlineField id="share-subheadline" label="Subheadline" value={subheadline} defaultValue={defaultSubheadline} maxLength={subheadlineMaxLength} onChange={onSubheadlineChange} onReset={onResetSubheadline} red />
          <ShareHeadlineField id="share-headline" label="Headline" value={headline} defaultValue={defaultHeadline} maxLength={headlineMaxLength} onChange={onHeadlineChange} onReset={onResetHeadline} />
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
    </Modal>
  );
}

function ShareFormatField({ format, onChange }: { format: ShareFormat; onChange?: (format: ShareFormat) => void }) {
  return (
    <fieldset>
      <legend className="mb-1.5 type-label font-semibold text-fg-muted">Instagram format</legend>
      <div className="grid grid-cols-2 gap-2">
        {(["post", "reel"] as const).map((value) => (
          <button key={value} type="button" onClick={() => onChange?.(value)} className={`border px-2.5 py-2 text-left ${format === value ? "border-panel bg-panel text-panel-fg" : "border-line bg-surface text-fg-muted"}`}>
            <span className="block type-label font-bold">Instagram {value}</span>
            <span className="mt-0.5 block font-mono text-[10px] opacity-70">{value === "post" ? "4:5 · 1080 × 1350" : "9:16 · 1080 × 1920"}</span>
          </button>
        ))}
      </div>
    </fieldset>
  );
}

function ShareHeadlineField({ id, label, value, defaultValue, maxLength, onChange, onReset, red = false }: { id: string; label: string; value?: string; defaultValue?: string; maxLength: number; onChange?: (value: string) => void; onReset?: () => void; red?: boolean }) {
  return (
    <div>
      <label htmlFor={id} className="mb-1.5 block type-label font-semibold text-fg-muted">{label}</label>
      <div className="flex gap-2">
        <input id={id} value={value} maxLength={maxLength} onChange={(event) => onChange?.(event.target.value)} className={`min-w-0 flex-1 border border-line bg-surface px-2.5 py-2 ${red ? "font-mono text-xs font-semibold tracking-[0.12em] text-[#c9382c]" : "font-slab text-sm text-fg"} uppercase outline-none focus:border-fg-muted`} />
        {value !== defaultValue ? <button type="button" onClick={onReset} className="shrink-0 type-label text-fg-muted hover:text-fg">Reset</button> : null}
      </div>
    </div>
  );
}
