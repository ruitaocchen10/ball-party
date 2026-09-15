"use client";

import type { FormEvent } from "react";

import { AuthorAvatar } from "./AuthorIdentity";

/** A compact, inline reply control for a focused take discussion. */
export function TakeReplyComposer({
  takeId,
  displayName,
  avatarUrl,
  body,
  pending,
  error,
  onBodyChange,
  onSubmit,
}: {
  takeId: string;
  displayName: string;
  avatarUrl: string | null;
  body: string;
  pending: boolean;
  error: string | null;
  onBodyChange: (body: string) => void;
  onSubmit: () => void;
}) {
  function submit(event: FormEvent<HTMLFormElement>) {
    event.preventDefault();
    onSubmit();
  }

  return (
    <form onSubmit={submit}>
      <div className="flex items-center gap-3">
        <AuthorAvatar name={displayName} avatarUrl={avatarUrl} />
        <label htmlFor={`take-comment-${takeId}`} className="sr-only">Post your reply</label>
        <input
          id={`take-comment-${takeId}`}
          type="text"
          value={body}
          onChange={(event) => onBodyChange(event.target.value)}
          maxLength={280}
          placeholder="Post your reply"
          className="min-w-0 flex-1 bg-transparent text-lg text-fg placeholder:text-fg-muted focus:outline-none"
        />
        <button
          type="submit"
          disabled={pending || !body.trim()}
          className="shrink-0 rounded-full bg-fg px-5 py-2 text-sm font-semibold text-surface transition-opacity hover:opacity-85 disabled:cursor-not-allowed disabled:opacity-45 focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-panel"
        >
          {pending ? "Sending…" : "Reply"}
        </button>
      </div>
      {error ? <p role="alert" className="mt-2 font-mono text-[10px] tracking-[0.1em] text-grade-rough uppercase">{error}</p> : null}
    </form>
  );
}
