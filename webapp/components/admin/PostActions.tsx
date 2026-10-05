"use client";

import { useRouter } from "next/navigation";
import { useState } from "react";

import { resolvePromptPost, voidPromptPost } from "@/lib/foundation/content/prompts/client";
import { createClient } from "@/lib/supabase/client";

export type AdminSlot = {
  id: string;
  label: string;
  shape: string;
  pickCount: number | null;
  options: { id: string; label: string; sublabel: string | null }[];
};

type Mode = "resolve" | "void" | null;

const BUTTON =
  "border px-3 py-2 type-label font-bold transition-colors disabled:opacity-40";

/** How many answers a slot needs: pick is always one, the other shapes carry pick_count. */
function requiredCount(slot: AdminSlot) {
  return slot.shape === "pick" ? 1 : (slot.pickCount ?? slot.options.length);
}

/**
 * Resolve / void controls for one open or locked post. Nothing here decides
 * anything — prompts.resolve_post and prompts.void_post re-check the admin
 * and the post's state themselves — so this only collects the answers and
 * shows the RPC's own error if it refuses.
 *
 * Each action opens its own panel and only commits from the button inside
 * it: both are irreversible (resolve grades every response, void closes the
 * post for good), so there's no one-click path.
 */
export function PostActions({
  postId,
  slots,
  canResolve,
}: {
  postId: string;
  slots: AdminSlot[];
  /** False until the post's lock time has passed — resolving while people can still answer would grade a moving target. */
  canResolve: boolean;
}) {
  const router = useRouter();
  const [mode, setMode] = useState<Mode>(null);
  const [answers, setAnswers] = useState<Record<string, string[]>>({});
  const [reason, setReason] = useState("");
  const [error, setError] = useState<string | null>(null);
  const [busy, setBusy] = useState(false);

  const complete = slots.every((slot) => (answers[slot.id]?.length ?? 0) === requiredCount(slot));

  function open(next: Mode) {
    setMode(next);
    setError(null);
  }

  // Click order is the answer order, which is what rank slots grade on; for
  // pick and pick_set the order is simply ignored by the grader.
  function toggle(slot: AdminSlot, optionId: string) {
    setAnswers((current) => {
      const picked = current[slot.id] ?? [];
      if (picked.includes(optionId)) return { ...current, [slot.id]: picked.filter((id) => id !== optionId) };
      if (picked.length >= requiredCount(slot)) {
        // A pick slot swaps its single answer; the others must un-pick first.
        return slot.shape === "pick" ? { ...current, [slot.id]: [optionId] } : current;
      }
      return { ...current, [slot.id]: [...picked, optionId] };
    });
  }

  async function submit() {
    setBusy(true);
    setError(null);
    const supabase = createClient();
    const { error: rpcError } =
      mode === "resolve"
        ? await resolvePromptPost(supabase, { postId, answers })
        : await voidPromptPost(supabase, { postId, reason });
    setBusy(false);
    if (rpcError) {
      setError(rpcError);
      return;
    }
    router.refresh();
  }

  return (
    <div className="sm:col-span-2">
      <div className="flex gap-2">
        {canResolve ? (
          <button
            type="button"
            onClick={() => open(mode === "resolve" ? null : "resolve")}
            aria-expanded={mode === "resolve"}
            className={`${BUTTON} border-line text-fg-muted hover:border-fg hover:text-fg`}
          >
            Resolve
          </button>
        ) : null}
        <button
          type="button"
          onClick={() => open(mode === "void" ? null : "void")}
          aria-expanded={mode === "void"}
          className={`${BUTTON} border-line text-fg-muted hover:border-fg hover:text-fg`}
        >
          Void
        </button>
      </div>

      {mode === "resolve" ? (
        <div className="mt-4 space-y-5 border border-line p-4">
          {slots.map((slot) => {
            const picked = answers[slot.id] ?? [];
            const need = requiredCount(slot);
            return (
              <fieldset key={slot.id}>
                <legend className="text-sm font-semibold text-fg">{slot.label}</legend>
                <p className="mt-1 type-label text-fg-muted">
                  {slot.shape === "rank"
                    ? `Click ${need} in order, first place first`
                    : need === 1
                      ? "Pick the correct answer"
                      : `Pick the ${need} correct answers`}
                  {` · ${picked.length}/${need}`}
                </p>
                <div className="mt-3 flex flex-wrap gap-2">
                  {slot.options.map((option) => {
                    const position = picked.indexOf(option.id);
                    const selected = position !== -1;
                    return (
                      <button
                        key={option.id}
                        type="button"
                        aria-pressed={selected}
                        onClick={() => toggle(slot, option.id)}
                        className={`border px-3 py-2 text-left text-sm transition-colors ${
                          selected ? "border-fg bg-fg text-surface" : "border-line text-fg hover:border-fg"
                        }`}
                      >
                        {slot.shape === "rank" && selected ? <span className="mr-2 font-mono">{position + 1}.</span> : null}
                        {option.label}
                        {option.sublabel ? <span className="ml-2 opacity-70">{option.sublabel}</span> : null}
                      </button>
                    );
                  })}
                </div>
              </fieldset>
            );
          })}
          <p className="text-sm text-fg-muted">Resolving grades every response and can&apos;t be undone.</p>
          <button
            type="button"
            disabled={!complete || busy}
            onClick={submit}
            className={`${BUTTON} border-fg bg-fg text-surface`}
          >
            {busy ? "Resolving…" : "Confirm resolve"}
          </button>
        </div>
      ) : null}

      {mode === "void" ? (
        <div className="mt-4 space-y-3 border border-line p-4">
          <label className="block text-sm font-semibold text-fg" htmlFor={`void-reason-${postId}`}>
            Reason
          </label>
          <input
            id={`void-reason-${postId}`}
            value={reason}
            onChange={(event) => setReason(event.target.value)}
            maxLength={200}
            placeholder="Shown on the post, e.g. game postponed"
            className="w-full border border-line bg-transparent px-3 py-2 text-sm text-fg"
          />
          <p className="text-sm text-fg-muted">Voiding closes the post with no grading and can&apos;t be undone.</p>
          <button
            type="button"
            disabled={!reason.trim() || busy}
            onClick={submit}
            className={`${BUTTON} border-fg bg-fg text-surface`}
          >
            {busy ? "Voiding…" : "Confirm void"}
          </button>
        </div>
      ) : null}

      {error ? (
        <p role="alert" className="mt-3 text-sm text-fg">
          {error}
        </p>
      ) : null}
    </div>
  );
}
