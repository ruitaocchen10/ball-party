"use client";

import { useState } from "react";
import { useRouter } from "next/navigation";
import Link from "next/link";

import { AnimatedMessage } from "@/components/foundation/ui-kit/AnimatedMessage";
import { Button } from "@/components/foundation/ui-kit/Button";
import { Input } from "@/components/foundation/ui-kit/Input";
import { PASSWORD_MIN } from "@/lib/foundation/identity/types";
import { createClient } from "@/lib/supabase/client";

export function GuestUpgrade() {
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
    <section className="rounded-card bg-surface-raised p-4 shadow-well">
      <h2 className="font-slab text-xl leading-none uppercase">Keep this record</h2>
      <p className="mt-2 text-sm leading-5 text-fg-muted">Add an account and your games stay right where they are.</p>
      <form action={upgrade} className="mt-4 flex flex-col gap-2.5">
        <Input name="email" type="email" required autoComplete="email" placeholder="you@example.com" aria-label="Email" />
        <Input name="password" type="password" required minLength={PASSWORD_MIN} autoComplete="new-password" placeholder={`At least ${PASSWORD_MIN} characters`} aria-label="Password" />
        <AnimatedMessage role="alert" className="text-sm text-hidden-text">
          {error}
        </AnimatedMessage>
        <Button type="submit" disabled={pending}>{pending ? "Saving…" : "Keep my record"}</Button>
      </form>
      <Link href="/login" className="mt-4 block text-sm text-fg-muted underline decoration-line underline-offset-4">
        I already have an account
      </Link>
    </section>
  );
}
