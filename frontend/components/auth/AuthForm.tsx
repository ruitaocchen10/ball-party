"use client";

import Link from "next/link";
import { useActionState } from "react";
import { useFormStatus } from "react-dom";

import { signInWithEmail, signUpWithEmail } from "@/lib/auth/actions";
import {
  DISPLAY_NAME_MAX,
  DISPLAY_NAME_MIN,
  EMPTY_AUTH_STATE,
  PASSWORD_MIN,
  type AuthState,
} from "@/lib/auth/types";

import { GoogleButton } from "./GoogleButton";

const FIELD =
  "h-11 w-full rounded-lg border border-black/15 bg-transparent px-3 text-sm outline-none placeholder:text-black/35 focus:border-black/40 dark:border-white/20 dark:placeholder:text-white/35 dark:focus:border-white/50";

function Submit({ label }: { label: string }) {
  const { pending } = useFormStatus();

  return (
    <button
      type="submit"
      disabled={pending}
      className="h-11 w-full rounded-lg bg-foreground text-sm font-medium text-background transition-opacity hover:opacity-90 disabled:opacity-60"
    >
      {pending ? "Working…" : label}
    </button>
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
      <header className="flex flex-col gap-1.5">
        <h1 className="text-2xl font-semibold tracking-tight">
          {isSignup ? "Create your account" : "Sign in to Ball Party"}
        </h1>
        <p className="text-sm text-black/55 dark:text-white/55">
          {isSignup
            ? "You'll need an account to host or join a room."
            : "Welcome back."}
        </p>
      </header>

      {/* Sibling, not nested — forms can't contain forms. */}
      <GoogleButton next={next} label={isSignup ? "Sign up with Google" : "Sign in with Google"} />

      <div className="flex items-center gap-3 text-xs uppercase tracking-wide text-black/40 dark:text-white/40">
        <span className="h-px flex-1 bg-black/10 dark:bg-white/15" />
        or
        <span className="h-px flex-1 bg-black/10 dark:bg-white/15" />
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

        {state.error && (
          <p role="alert" className="text-sm text-red-600 dark:text-red-400">
            {state.error}
          </p>
        )}

        <div className="pt-1">
          <Submit label={isSignup ? "Create account" : "Sign in"} />
        </div>
      </form>

      <p className="text-sm text-black/55 dark:text-white/55">
        {isSignup ? "Already have an account? " : "New here? "}
        <Link
          href={isSignup ? "/login" : "/signup"}
          className="font-medium text-foreground underline underline-offset-4 decoration-black/30 dark:decoration-white/30"
        >
          {isSignup ? "Sign in" : "Create an account"}
        </Link>
      </p>
    </div>
  );
}
