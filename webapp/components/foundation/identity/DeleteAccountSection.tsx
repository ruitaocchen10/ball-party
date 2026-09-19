"use client";

import { useRouter } from "next/navigation";
import { useState, useTransition } from "react";

import { deleteAccount } from "@/app/settings/actions";
import { AnimatedMessage } from "@/components/foundation/ui-kit/AnimatedMessage";
import { Button } from "@/components/foundation/ui-kit/Button";

// Destructive, so it stays visually subordinate — same convention as
// LobbyTopStrip's "Close room": ghost + the hidden/red-adjacent tokens,
// since there's no dedicated destructive Button variant.
const DANGER_BUTTON = "min-h-9 px-3.5 text-[10px] text-hidden-text ring-hidden/40 hover:bg-hidden/10";

/** Two-step disclosure in place of a modal — one boolean is enough ceremony
 *  for a single confirm, and this is the only destructive control on the page. */
export function DeleteAccountSection() {
  const router = useRouter();
  const [confirming, setConfirming] = useState(false);
  const [pending, startTransition] = useTransition();
  const [error, setError] = useState<string | null>(null);

  function confirm() {
    setError(null);
    startTransition(async () => {
      try {
        await deleteAccount();
        router.push("/");
      } catch {
        setError("We couldn’t delete your account. Please try again.");
      }
    });
  }

  if (!confirming) {
    return (
      <Button type="button" variant="ghost" fullWidth={false} onClick={() => setConfirming(true)} className={DANGER_BUTTON}>
        Delete account
      </Button>
    );
  }

  return (
    <div className="grid gap-3">
      <p className="max-w-[48ch] text-sm leading-5 text-fg-muted">
        This clears your display name and photo and signs you out everywhere. Your past matches and takes stay on record under “Deleted player.” This can’t be undone.
      </p>
      <AnimatedMessage role="alert" className="text-sm text-hidden-text">
        {error}
      </AnimatedMessage>
      <div className="flex flex-wrap gap-2.5">
        <Button type="button" variant="ghost" fullWidth={false} disabled={pending} onClick={confirm} className={DANGER_BUTTON}>
          {pending ? "Deleting…" : "Yes, permanently delete my account"}
        </Button>
        <Button type="button" variant="ghost" fullWidth={false} disabled={pending} onClick={() => setConfirming(false)} className="min-h-9 px-3.5 text-[10px]">
          Cancel
        </Button>
      </div>
    </div>
  );
}
