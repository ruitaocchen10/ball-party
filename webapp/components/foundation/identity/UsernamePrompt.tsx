"use client";

import { useRef, useState, useSyncExternalStore, useTransition } from "react";

import { claimUsername } from "@/app/profile/actions";
import { AnimatedMessage } from "@/components/foundation/ui-kit/AnimatedMessage";
import { Button } from "@/components/foundation/ui-kit/Button";
import { Modal, ModalTitle } from "@/components/foundation/ui-kit/Modal";
import { isUsernameConfirmed, markUsernameConfirmed, usernameFormatHint } from "@/lib/foundation/identity/username";

import { UsernameField } from "./UsernameField";

/**
 * One-time prompt asking an account holder to confirm the username they were
 * given (generated from their display name, or the one they typed at signup
 * when it couldn't be claimed before their email was confirmed).
 *
 * "Confirmed" is remembered per browser in localStorage: there is no server
 * flag. Saving, keeping, closing or skipping all count, so it never reappears
 * on that browser.
 */
export function UsernamePrompt({
  userId,
  currentUsername,
  preferredUsername,
}: {
  userId: string;
  currentUsername: string;
  /** A username chosen at signup that differs from the assigned one, if any. */
  preferredUsername?: string | null;
}) {
  const [dismissed, setDismissed] = useState(false);
  const [value, setValue] = useState(preferredUsername || currentUsername);
  const [error, setError] = useState<string | null>(null);
  const [pending, startTransition] = useTransition();
  const input = useRef<HTMLInputElement>(null);

  // localStorage doesn't exist during server rendering, so the server snapshot
  // says "confirmed" (render nothing) and the client reads the real value.
  const confirmed = useSyncExternalStore(
    subscribeToStorage,
    () => isUsernameConfirmed(userId),
    () => true,
  );

  if (confirmed || dismissed) return null;

  function dismiss() {
    markUsernameConfirmed(userId);
    setDismissed(true);
  }

  function save() {
    const next = value.trim();
    if (next === currentUsername) return dismiss();
    const hint = usernameFormatHint(next);
    if (hint) return setError(hint);

    setError(null);
    startTransition(async () => {
      const result = await claimUsername(next);
      if (result.error) return setError(result.error);
      dismiss();
    });
  }

  const changed = value.trim() !== currentUsername;

  return (
    <Modal onClose={dismiss} closeLabel="Skip choosing a username" initialFocusRef={input}>
      <form
        onSubmit={(event) => {
          event.preventDefault();
          save();
        }}
      >
        <div className="pr-10">
          <p className="type-label font-semibold text-hidden-text">Your username</p>
          <ModalTitle className="mt-1 font-slab text-3xl uppercase">Is this you?</ModalTitle>
          <p className="mt-2 text-sm text-fg-muted">
            Friends will find you by your username. We picked one from your name — keep it or change it now.
          </p>
        </div>
        <div className="mt-5">
          <UsernameField value={value} onChange={setValue} currentUsername={currentUsername} inputRef={input} />
        </div>
        <AnimatedMessage role="alert" className="mt-3 text-sm text-hidden-text">
          {error}
        </AnimatedMessage>
        <div className="mt-5 flex gap-2.5">
          <Button size="sm" fullWidth={false} type="submit" disabled={pending}>
            {pending ? "Saving…" : changed ? "Save username" : "Keep this username"}
          </Button>
          <Button variant="text" size="sm" fullWidth={false} type="button" disabled={pending} onClick={dismiss}>
            Skip
          </Button>
        </div>
      </form>
    </Modal>
  );
}

function subscribeToStorage(onChange: () => void) {
  window.addEventListener("storage", onChange);
  return () => window.removeEventListener("storage", onChange);
}
