"use client";

import { useState } from "react";
import { useRouter } from "next/navigation";

import { Button } from "@/components/ui/Button";
import { createClient } from "@/lib/supabase/client";
import { DISPLAY_NAME_MAX, DISPLAY_NAME_MIN } from "@/lib/auth/types";

export function GuestJoin() {
  const router = useRouter();
  const [error, setError] = useState<string | null>(null);
  const [pending, setPending] = useState(false);

  async function join(formData: FormData) {
    const displayName = String(formData.get("display_name") ?? "").trim();
    if (displayName.length < DISPLAY_NAME_MIN || displayName.length > DISPLAY_NAME_MAX) {
      setError(`Display name must be ${DISPLAY_NAME_MIN}–${DISPLAY_NAME_MAX} characters.`);
      return;
    }

    setPending(true);
    setError(null);
    const { error: signInError } = await createClient().auth.signInAnonymously({
      options: { data: { display_name: displayName } },
    });
    if (signInError) {
      setError(signInError.message);
      setPending(false);
      return;
    }
    router.refresh();
  }

  return (
    <form action={join} className="flex flex-col gap-2.5">
      <label className="flex flex-col gap-1.5">
        <span className="text-sm font-medium">Your name</span>
        <input
          name="display_name"
          required
          minLength={DISPLAY_NAME_MIN}
          maxLength={DISPLAY_NAME_MAX}
          autoComplete="nickname"
          placeholder="What your friends will see"
          className="h-12 rounded border border-line bg-surface-raised px-3 text-sm text-fg outline-none placeholder:text-fg-muted focus:border-panel"
        />
      </label>
      {error ? <p role="alert" className="text-sm text-hidden-text">{error}</p> : null}
      <Button type="submit" disabled={pending}>{pending ? "Joining…" : "Join as guest"}</Button>
      <p className="text-xs leading-5 text-fg-muted">You&apos;re playing without an account. Add one later to keep this record.</p>
    </form>
  );
}
