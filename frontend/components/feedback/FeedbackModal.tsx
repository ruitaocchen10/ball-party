"use client";

import { Bug, Lightbulb, X } from "lucide-react";
import { useActionState, useEffect, useRef, useState } from "react";

import { submitFeedback } from "@/lib/feedback/actions";
import { EMPTY_FEEDBACK_STATE } from "@/lib/feedback/state";

type FeedbackKind = "bug" | "feature";

export function FeedbackModal({ route, onClose }: { route: string; onClose: () => void }) {
  const [kind, setKind] = useState<FeedbackKind>("bug");
  const [state, formAction, pending] = useActionState(submitFeedback, EMPTY_FEEDBACK_STATE);
  const messageInput = useRef<HTMLTextAreaElement>(null);

  useEffect(() => {
    messageInput.current?.focus();
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
    <div className="fixed inset-0 z-40 flex items-center justify-center p-4" role="presentation">
      <button type="button" aria-label="Close feedback" onClick={onClose} className="absolute inset-0 bg-black/60" />
      <section role="dialog" aria-modal="true" aria-labelledby="feedback-title" className="relative w-full max-w-md bg-surface-raised p-5 shadow-card">
        <button type="button" onClick={onClose} aria-label="Close feedback" className="absolute top-4 right-4 flex h-9 w-9 items-center justify-center text-fg-muted hover:text-fg focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-panel">
          <X className="h-5 w-5" strokeWidth={1.5} />
        </button>

        {state.saved ? (
          <div className="pr-10">
            <h2 id="feedback-title" className="font-slab text-3xl uppercase">Thanks.</h2>
            <p className="mt-2 text-sm text-fg-muted">Your feedback has been sent to the Ball Party team.</p>
            <button type="button" onClick={onClose} className="mt-5 bg-panel px-3.5 py-2.5 font-mono text-xs font-bold tracking-[0.13em] text-panel-fg uppercase">Done</button>
          </div>
        ) : (
          <form action={formAction}>
            <div className="pr-10">
              <p className="font-mono text-xs font-semibold tracking-[0.13em] text-fg-muted uppercase">Feedback</p>
              <h2 id="feedback-title" className="mt-1 font-slab text-3xl uppercase">Help shape the game</h2>
            </div>
            <fieldset className="mt-5 grid grid-cols-2 gap-2">
              <legend className="sr-only">Feedback type</legend>
              <FeedbackTypeButton kind="bug" selected={kind === "bug"} onSelect={setKind} />
              <FeedbackTypeButton kind="feature" selected={kind === "feature"} onSelect={setKind} />
            </fieldset>
            <input type="hidden" name="kind" value={kind} />
            <input type="hidden" name="route" value={route} />
            <label className="mt-5 block font-mono text-xs font-semibold tracking-[0.1em] text-fg-muted uppercase">
              {kind === "bug" ? "What went wrong?" : "What would you like to see?"}
              <textarea ref={messageInput} name="message" required minLength={3} maxLength={2000} rows={5} placeholder={kind === "bug" ? "Tell us what happened and what you expected." : "Describe the feature that would help."} className="mt-2 block w-full resize-y border border-line bg-surface px-3 py-2.5 font-sans text-sm normal-case tracking-normal text-fg outline-none placeholder:text-fg-muted focus:border-panel" />
            </label>
            {state.error ? <p role="alert" className="mt-3 text-sm text-hidden-text">{state.error}</p> : null}
            <div className="mt-5 flex items-center gap-3">
              <button type="submit" disabled={pending} className="bg-panel px-3.5 py-2.5 font-mono text-xs font-bold tracking-[0.13em] text-panel-fg uppercase disabled:opacity-60">{pending ? "Sending…" : "Send feedback"}</button>
              <button type="button" onClick={onClose} className="font-mono text-xs tracking-[0.1em] text-fg-muted uppercase hover:text-fg">Cancel</button>
            </div>
          </form>
        )}
      </section>
    </div>
  );
}

function FeedbackTypeButton({ kind, selected, onSelect }: { kind: FeedbackKind; selected: boolean; onSelect: (kind: FeedbackKind) => void }) {
  const Icon = kind === "bug" ? Bug : Lightbulb;
  const label = kind === "bug" ? "Report a bug" : "Request a feature";
  return (
    <button type="button" onClick={() => onSelect(kind)} aria-pressed={selected} className={`flex items-center gap-2 border px-3 py-3 text-left font-mono text-xs font-semibold tracking-[0.06em] uppercase transition-colors focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-panel ${selected ? "border-panel bg-panel text-panel-fg" : "border-line text-fg-muted hover:border-fg-muted hover:text-fg"}`}>
      <Icon className="h-5 w-5 shrink-0" strokeWidth={1.5} />
      {label}
    </button>
  );
}
