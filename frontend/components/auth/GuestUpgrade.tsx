"use client";

import { useState } from "react";
import { useRouter } from "next/navigation";
import Link from "next/link";

import { Button } from "@/components/ui/Button";
import { PASSWORD_MIN } from "@/lib/auth/types";
import { createClient } from "@/lib/supabase/client";

export function GuestUpgrade({ guestId }: { guestId: string }) {
  const router = useRouter();
  const [error, setError] = useState<string | null>(null);
  const [pending, setPending] = useState(false);

  async function upgrade(formData: FormData) {
    const email = String(formData.get("email") ?? "").trim().toLowerCase();
    const password = String(formData.get("password") ?? "");
    setPending(true);
    setError(null);
    const { error: updateError } = await createClient().auth.updateUser({ email, password });
    if (updateError) {
      setError(updateError.message);
      setPending(false);
      return;
    }
    router.refresh();
  }

  return (
    <section className="rounded-card border border-line bg-surface-raised p-4">
      <h2 className="font-slab text-xl leading-none -skew-x-7 uppercase">Keep this record</h2>
      <p className="mt-2 text-sm leading-5 text-fg-muted">Add an account and your games stay right where they are.</p>
      <form action={upgrade} className="mt-4 flex flex-col gap-2.5">
        <input name="email" type="email" required autoComplete="email" placeholder="you@example.com" className="h-12 rounded border border-line bg-surface px-3 text-sm" />
        <input name="password" type="password" required minLength={PASSWORD_MIN} autoComplete="new-password" placeholder={`At least ${PASSWORD_MIN} characters`} className="h-12 rounded border border-line bg-surface px-3 text-sm" />
        {error ? <p role="alert" className="text-sm text-hidden-text">{error}</p> : null}
        <Button type="submit" disabled={pending}>{pending ? "Saving…" : "Keep my record"}</Button>
      </form>
      <Link href={`/login?guest=${encodeURIComponent(guestId)}`} className="mt-4 block text-sm text-fg-muted underline decoration-line underline-offset-4">
        I already have an account
      </Link>
    </section>
  );
}
