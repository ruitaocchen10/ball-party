"use client";

import { useRef, useState } from "react";

import { AnimatedMessage } from "@/components/foundation/ui-kit/AnimatedMessage";
import { Button } from "@/components/foundation/ui-kit/Button";
import { PASSWORD_MIN } from "@/lib/foundation/identity/types";
import { createClient } from "@/lib/supabase/client";

const FIELD =
  "mt-1.5 block w-full border border-line bg-surface px-3 py-2.5 font-sans text-sm normal-case tracking-normal text-fg outline-none focus:border-panel";
const LABEL = "block font-mono text-[10px] tracking-[0.12em] text-fg-muted uppercase";

/** Credential changes go straight through `auth.updateUser` client-side — the
 *  same call GuestUpgrade already makes — rather than a server action, since
 *  there's no app data to validate beyond what Supabase itself enforces. */
export function AccountCredentials({ email, providers }: { email: string; providers: string[] }) {
  return (
    <div className="grid gap-7">
      <EmailForm currentEmail={email} />
      <PasswordForm />
      <ConnectedAccounts providers={providers} />
    </div>
  );
}

function EmailForm({ currentEmail }: { currentEmail: string }) {
  const [pending, setPending] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [saved, setSaved] = useState(false);

  async function submit(formData: FormData) {
    const email = String(formData.get("email") ?? "").trim().toLowerCase();
    setPending(true);
    setError(null);
    setSaved(false);
    const { error: updateError } = await createClient().auth.updateUser({ email });
    setPending(false);
    if (updateError) {
      setError(updateError.message);
      return;
    }
    setSaved(true);
  }

  return (
    <form action={submit} className="grid gap-2.5">
      <label className={LABEL}>
        Email address
        <input name="email" type="email" required defaultValue={currentEmail} autoComplete="email" className={FIELD} />
      </label>
      <AnimatedMessage role="alert" className="text-sm text-hidden-text">
        {error}
      </AnimatedMessage>
      <AnimatedMessage role="status" className="text-sm text-fg-muted">
        {saved ? "Check both your old and new inbox to confirm the change." : null}
      </AnimatedMessage>
      <Button type="submit" variant="ghost" fullWidth={false} disabled={pending} className="min-h-9 px-3.5 text-[10px]">
        {pending ? "Saving…" : "Update email"}
      </Button>
    </form>
  );
}

function PasswordForm() {
  const formRef = useRef<HTMLFormElement>(null);
  const [pending, setPending] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [saved, setSaved] = useState(false);

  async function submit(formData: FormData) {
    const password = String(formData.get("password") ?? "");
    setPending(true);
    setError(null);
    setSaved(false);
    const { error: updateError } = await createClient().auth.updateUser({ password });
    setPending(false);
    if (updateError) {
      setError(updateError.message);
      return;
    }
    formRef.current?.reset();
    setSaved(true);
  }

  return (
    <form ref={formRef} action={submit} className="grid gap-2.5">
      <label className={LABEL}>
        New password
        <input
          name="password"
          type="password"
          required
          minLength={PASSWORD_MIN}
          autoComplete="new-password"
          placeholder={`At least ${PASSWORD_MIN} characters`}
          className={FIELD}
        />
      </label>
      <AnimatedMessage role="alert" className="text-sm text-hidden-text">
        {error}
      </AnimatedMessage>
      <AnimatedMessage role="status" className="text-sm text-fg-muted">
        {saved ? "Password updated." : null}
      </AnimatedMessage>
      <Button type="submit" variant="ghost" fullWidth={false} disabled={pending} className="min-h-9 px-3.5 text-[10px]">
        {pending ? "Saving…" : "Update password"}
      </Button>
    </form>
  );
}

function ConnectedAccounts({ providers }: { providers: string[] }) {
  if (providers.length === 0) return null;

  return (
    <div>
      <p className={LABEL}>Connected accounts</p>
      <ul className="mt-2 grid gap-1.5">
        {providers.map((provider) => (
          <li key={provider} className="text-sm text-fg-muted">
            <span className="capitalize text-fg">{provider}</span> — connected
          </li>
        ))}
      </ul>
    </div>
  );
}
