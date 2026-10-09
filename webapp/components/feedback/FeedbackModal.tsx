"use client";

import { Bug, Lightbulb } from "lucide-react";
import { useActionState, useRef, useState } from "react";

import { submitFeedback } from "@/lib/feedback/actions";
import { EMPTY_FEEDBACK_STATE } from "@/lib/feedback/state";
import { Field, Textarea } from "@/components/foundation/ui-kit/Input";
import { Modal, ModalTitle } from "@/components/foundation/ui-kit/Modal";
import { Button } from "@/components/foundation/ui-kit/Button";

type FeedbackKind = "bug" | "feature";

export function FeedbackModal({ route, onClose }: { route: string; onClose: () => void }) {
  const [kind, setKind] = useState<FeedbackKind>("bug");
  const [state, formAction, pending] = useActionState(submitFeedback, EMPTY_FEEDBACK_STATE);
  const messageInput = useRef<HTMLTextAreaElement>(null);

  return (
    <Modal onClose={onClose} closeLabel="Close feedback" initialFocusRef={messageInput}>
      {state.saved ? (
        <div className="pr-10">
          <ModalTitle className="font-slab text-3xl uppercase">Thanks.</ModalTitle>
          <p className="mt-2 text-sm text-fg-muted">Your feedback has been sent to the Ball Party team.</p>
          <Button size="sm" fullWidth={false} className="mt-5" type="button" onClick={onClose}>Done</Button>
        </div>
      ) : (
        <form action={formAction}>
          <div className="pr-10">
            <p className="font-mono text-xs font-semibold tracking-[0.13em] text-fg-muted uppercase">Feedback</p>
            <ModalTitle className="mt-1 font-slab text-3xl uppercase">Help shape the game</ModalTitle>
          </div>
          <fieldset className="mt-5 grid grid-cols-2 gap-2">
            <legend className="sr-only">Feedback type</legend>
            <FeedbackTypeButton kind="bug" selected={kind === "bug"} onSelect={setKind} />
            <FeedbackTypeButton kind="feature" selected={kind === "feature"} onSelect={setKind} />
          </fieldset>
          <input type="hidden" name="kind" value={kind} />
          <input type="hidden" name="route" value={route} />
          <Field label={kind === "bug" ? "What went wrong?" : "What would you like to see?"} className="mt-5">
            <Textarea
              ref={messageInput}
              name="message"
              required
              minLength={3}
              maxLength={2000}
              rows={5}
              placeholder={kind === "bug" ? "Tell us what happened and what you expected." : "Describe the feature that would help."}
            />
          </Field>
          {state.error ? <p role="alert" className="mt-3 text-sm text-hidden-text">{state.error}</p> : null}
          <div className="mt-5 flex items-center gap-3">
            <Button size="sm" fullWidth={false} type="submit" disabled={pending}>{pending ? "Sending…" : "Send feedback"}</Button>
            <Button variant="text" size="sm" fullWidth={false} type="button" onClick={onClose}>Cancel</Button>
          </div>
        </form>
      )}
    </Modal>
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
