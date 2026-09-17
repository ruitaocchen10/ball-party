"use client";

import { useState, useTransition } from "react";

import { updateRankingsVisibility } from "@/app/settings/actions";
import { AnimatedMessage } from "@/components/foundation/ui-kit/AnimatedMessage";

/** Saves on toggle rather than behind a separate button — there's only one
 *  field, and it's called directly rather than via a `<form action>` (see
 *  updateRankingsVisibility's own comment for why). */
export function RankingsVisibilityToggle({ initialVisible }: { initialVisible: boolean }) {
  const [checked, setChecked] = useState(initialVisible);
  const [pending, startTransition] = useTransition();
  const [error, setError] = useState<string | null>(null);

  function toggle(next: boolean) {
    setChecked(next);
    setError(null);
    startTransition(async () => {
      const result = await updateRankingsVisibility(next);
      if (result.error) {
        setError(result.error);
        setChecked(!next);
      }
    });
  }

  return (
    <div>
      <label className="flex items-start gap-3">
        <input
          type="checkbox"
          checked={checked}
          disabled={pending}
          onChange={(event) => toggle(event.target.checked)}
          className="mt-1 h-4 w-4 shrink-0 accent-panel-fg"
        />
        <span>
          <span className="block text-sm font-semibold text-fg">Show me in Knower rankings</span>
          <span className="mt-1 block max-w-[48ch] text-sm leading-5 text-fg-muted">
            Turn this off to leave the Ball Knower percentile comparison. Your own point total keeps counting — it just stops counting toward anyone else’s standing.
          </span>
        </span>
      </label>
      <AnimatedMessage role="alert" className="mt-2 text-sm text-hidden-text">
        {error}
      </AnimatedMessage>
    </div>
  );
}
