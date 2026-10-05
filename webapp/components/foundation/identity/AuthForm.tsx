"use client";

import Link from "next/link";
import { useActionState } from "react";
import { useFormStatus } from "react-dom";

import { AnimatedMessage } from "@/components/foundation/ui-kit/AnimatedMessage";
import { Button } from "@/components/foundation/ui-kit/Button";
import { signInWithEmail, signUpWithEmail } from "@/lib/foundation/identity/actions";
import {
  DISPLAY_NAME_MAX,
  DISPLAY_NAME_MIN,
  EMPTY_AUTH_STATE,
  PASSWORD_MIN,
  type AuthState,
} from "@/lib/foundation/identity/types";

import { GoogleButton } from "./GoogleButton";

// Fields are wells cut into the background, not panels — three cream blocks would
// blow out a screen whose whole premise is that light is rare.
const FIELD =
  "h-12 w-full border border-line bg-surface-raised px-3 text-sm text-fg outline-none placeholder:text-fg-muted focus:border-panel";

function Submit({ label }: { label: string }) {
  const { pending } = useFormStatus();

  return (
    <Button type="submit" disabled={pending}>
      {pending ? "Working…" : label}
    </Button>
  );
}

export function AuthForm({ mode, next }: { mode: "login" | "signup"; next: string }) {
  const isSignup = mode === "signup";
  const [state, formAction] = useActionState<AuthState, FormData>(
    isSignup ? signUpWithEmail : signInWithEmail,
    EMPTY_AUTH_STATE,
  );

  return (
    <div className="flex w-full flex-col gap-6">
      <header className="flex flex-col gap-2">
        <h1 className="font-slab text-3xl leading-none uppercase">
          {isSignup ? "Get in the game" : "Ball Party"}
        </h1>
        <p className="type-label text-fg-muted">
          {isSignup
            ? "Takes about ten seconds"
            : "Sign in to start or join a room"}
        </p>
      </header>

      {/* Sibling, not nested — forms can't contain forms. */}
      <GoogleButton next={next} label={isSignup ? "Sign up with Google" : "Sign in with Google"} />

      <div className="flex items-center gap-3 type-label text-fg-muted">
        <span className="h-px flex-1 bg-line" />
        or
        <span className="h-px flex-1 bg-line" />
      </div>

      <form action={formAction} className="flex flex-col gap-3">
        <input type="hidden" name="next" value={next} />

        {isSignup && (
          <label className="flex flex-col gap-1.5">
            <span className="text-sm font-medium">Display name</span>
            <input
              name="display_name"
              type="text"
              required
              minLength={DISPLAY_NAME_MIN}
              maxLength={DISPLAY_NAME_MAX}
              autoComplete="nickname"
              placeholder="What your friends will see"
              className={FIELD}
            />
          </label>
        )}

        <label className="flex flex-col gap-1.5">
          <span className="text-sm font-medium">Email</span>
          <input
            name="email"
            type="email"
            required
            autoComplete="email"
            placeholder="you@example.com"
            className={FIELD}
          />
        </label>

        <label className="flex flex-col gap-1.5">
          <span className="text-sm font-medium">Password</span>
          <input
            name="password"
            type="password"
            required
            minLength={isSignup ? PASSWORD_MIN : undefined}
            autoComplete={isSignup ? "new-password" : "current-password"}
            placeholder={isSignup ? `At least ${PASSWORD_MIN} characters` : ""}
            className={FIELD}
          />
        </label>

        {/* The one place red isn't about hidden information. Inventing a second
            alarm colour would cost more than reusing this one. */}
        <AnimatedMessage role="alert" className="text-sm text-hidden-text">
          {state.error}
        </AnimatedMessage>

        <div className="pt-1">
          <Submit label={isSignup ? "Create account" : "Sign in"} />
        </div>
      </form>

      <p className="text-sm text-fg-muted">
        {isSignup ? "Already have an account? " : "New here? "}
        <Link
          href={isSignup ? "/login" : "/signup"}
          className="font-medium text-fg underline decoration-line underline-offset-4 hover:decoration-fg"
        >
          {isSignup ? "Sign in" : "Create an account"}
        </Link>
      </p>
    </div>
  );
}
