"use client";

import { useRouter } from "next/navigation";
import { useRef, useState } from "react";

import { Button } from "@/components/foundation/ui-kit/Button";
import { Field, Textarea } from "@/components/foundation/ui-kit/Input";
import { Modal, ModalTitle } from "@/components/foundation/ui-kit/Modal";
import {
  REPORT_REASONS,
  sendReport,
  type ReportReason,
  type ReportTarget,
} from "@/lib/foundation/moderation/reports";
import { createClient } from "@/lib/supabase/client";

/**
 * The form behind every Report button. The reporter picks a reason and may add
 * a note; the server records it for review and hides a reported take from the
 * reporter at once, so `onSent` is where the caller refreshes the page.
 */
export function ReportDialog({
  target,
  subject,
  onClose,
  refreshOnSent = false,
}: {
  target: ReportTarget;
  /** What is being reported, in the dialog's own words: "this take", "Sam's profile". */
  subject: string;
  onClose: () => void;
  /** Refresh the page once the report is sent, for a report that hides something from the reporter. */
  refreshOnSent?: boolean;
}) {
  const router = useRouter();
  const [reason, setReason] = useState<ReportReason | null>(null);
  const [details, setDetails] = useState("");
  const [pending, setPending] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [sent, setSent] = useState(false);
  const firstRef = useRef<HTMLInputElement>(null);

  async function submit(event: React.FormEvent) {
    event.preventDefault();
    if (!reason) return;
    setPending(true);
    setError(null);
    const message = await sendReport(createClient(), target, { reason, details });
    setPending(false);
    if (message) {
      setError(message);
      return;
    }
    setSent(true);
  }

  function done() {
    if (sent && refreshOnSent) router.refresh();
    onClose();
  }

  return (
    <Modal onClose={done} closeLabel="Close report" initialFocusRef={firstRef}>
      <ModalTitle className="font-slab text-3xl uppercase">{sent ? "Report sent" : `Report ${subject}`}</ModalTitle>
      {sent ? (
        <>
          <p className="mt-2 text-sm leading-6 text-fg-muted">
            Thanks. We review every report. {target.kind === "take" ? "You won't see this take again." : "You can also block them from their profile."}
          </p>
          <div className="mt-5">
            <Button onClick={done}>Done</Button>
          </div>
        </>
      ) : (
        <form onSubmit={submit} className="mt-3 flex flex-col gap-4">
          <fieldset className="flex flex-col gap-2">
            <legend className="type-label text-fg-muted">Why are you reporting this?</legend>
            {REPORT_REASONS.map((option, index) => (
              <label key={option.value} className="flex cursor-pointer items-center gap-3 text-sm">
                <input
                  ref={index === 0 ? firstRef : undefined}
                  type="radio"
                  name="reason"
                  value={option.value}
                  checked={reason === option.value}
                  onChange={() => setReason(option.value)}
                  className="h-4 w-4 accent-[var(--color-hidden)]"
                />
                {option.label}
              </label>
            ))}
          </fieldset>
          <Field label="Anything else we should know? (optional)" variant="dark">
            <Textarea variant="well" rows={3} maxLength={500} value={details} onChange={(e) => setDetails(e.target.value)} />
          </Field>
          {error ? <p role="alert" className="text-sm text-hidden-text">{error}</p> : null}
          <div className="flex gap-2">
            <Button type="submit" disabled={!reason || pending}>{pending ? "Sending…" : "Send report"}</Button>
            <Button type="button" variant="text" fullWidth={false} onClick={onClose}>Cancel</Button>
          </div>
        </form>
      )}
    </Modal>
  );
}
