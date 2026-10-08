"use client";

import { useState, useTransition } from "react";

import { setProfilePrivate } from "@/app/settings/actions";
import { AnimatedMessage } from "@/components/foundation/ui-kit/AnimatedMessage";

/** Saves on toggle rather than behind a separate button — there's only one
 *  field, and it's called directly rather than via a `<form action>` (see
 *  setProfilePrivate's own comment for why). */
export function PrivateProfileToggle({ initialPrivate }: { initialPrivate: boolean }) {
  const [checked, setChecked] = useState(initialPrivate);
  const [pending, startTransition] = useTransition();
  const [error, setError] = useState<string | null>(null);

  function toggle(next: boolean) {
    setChecked(next);
    setError(null);
    startTransition(async () => {
      const result = await setProfilePrivate(next);
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
          <span className="block text-sm font-semibold text-fg">Private profile</span>
          <span className="mt-1 block max-w-[48ch] text-sm leading-5 text-fg-muted">
            Only your friends can open your profile. Your name, username and photo still show in search, and you still appear in rankings.
          </span>
        </span>
      </label>
      <AnimatedMessage role="alert" className="mt-2 text-sm text-hidden-text">
        {error}
      </AnimatedMessage>
    </div>
  );
}
