"use client";

import { useEffect, useRef, useState, type Ref } from "react";

import { checkUsernameAvailable } from "@/app/profile/actions";
import { Field, Input } from "@/components/foundation/ui-kit/Input";
import { USERNAME_HINT, usernameFormatHint } from "@/lib/foundation/identity/username";

const DEBOUNCE_MS = 400;

type Status =
  | { kind: "idle" }
  | { kind: "checking" }
  | { kind: "available" }
  | { kind: "unavailable" }
  | { kind: "error"; message: string };

/**
 * A username input with a debounced availability check against the
 * `username_available` RPC (via a server action). The check is advisory: the
 * RPC behind `claim_username` is what actually decides on submit.
 *
 * `currentUsername` is the player's present name, which is never "taken" by
 * themselves. Pass `checkAvailability={false}` where there is no session to
 * ask with (signup), which leaves just the format hint.
 */
export function UsernameField({
  name = "username",
  label = "Username",
  value,
  onChange,
  currentUsername,
  checkAvailability = true,
  variant = "dark",
  inputRef,
  placeholder,
  help,
}: {
  name?: string;
  label?: string;
  value: string;
  onChange: (value: string) => void;
  currentUsername?: string | null;
  checkAvailability?: boolean;
  variant?: "dark" | "panel";
  inputRef?: Ref<HTMLInputElement>;
  placeholder?: string;
  help?: string;
}) {
  const [status, setStatus] = useState<Status>({ kind: "idle" });
  const latest = useRef(0);

  const trimmed = value.trim();
  const formatHint = trimmed ? usernameFormatHint(trimmed) : null;
  const unchanged = currentUsername != null && trimmed === currentUsername;
  const shouldCheck = checkAvailability && trimmed !== "" && !formatHint && !unchanged;

  useEffect(() => {
    const ticket = ++latest.current;
    if (!shouldCheck) {
      setStatus({ kind: "idle" });
      return;
    }
    setStatus({ kind: "checking" });
    const timer = setTimeout(async () => {
      const result = await checkUsernameAvailable(trimmed);
      if (ticket !== latest.current) return; // a newer keystroke superseded this answer
      if (result.available === null) setStatus({ kind: "error", message: result.error ?? "Couldn’t check that username." });
      else setStatus({ kind: result.available ? "available" : "unavailable" });
    }, DEBOUNCE_MS);
    return () => clearTimeout(timer);
  }, [shouldCheck, trimmed]);

  let message: string = help ?? USERNAME_HINT;
  let tone: "muted" | "error" | "ok" = "muted";
  if (formatHint) {
    message = formatHint;
    tone = "error";
  } else if (unchanged) {
    message = "That’s your current username.";
  } else if (status.kind === "checking") {
    message = "Checking…";
  } else if (status.kind === "available") {
    message = "Available.";
    tone = "ok";
  } else if (status.kind === "unavailable") {
    message = "That username isn’t available.";
    tone = "error";
  } else if (status.kind === "error") {
    message = status.message;
    tone = "error";
  }

  return (
    <Field label={label} variant={variant}>
      <Input
        ref={inputRef}
        variant={variant}
        name={name}
        type="text"
        value={value}
        onChange={(event) => onChange(event.target.value)}
        autoComplete="username"
        autoCapitalize="none"
        autoCorrect="off"
        spellCheck={false}
        placeholder={placeholder}
        aria-invalid={tone === "error"}
      />
      <span
        role="status"
        className={`text-xs leading-5 ${
          tone === "error" ? "text-hidden-text" : tone === "ok" ? "text-fg" : variant === "panel" ? "text-panel-muted" : "text-fg-muted"
        }`}
      >
        {message}
      </span>
    </Field>
  );
}
