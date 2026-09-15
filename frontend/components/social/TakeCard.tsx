"use client";

import { ChevronDown, ChevronUp } from "lucide-react";
import { type ReactNode, useState } from "react";

import { Button } from "@/components/ui/Button";
import { initials, relativeTime } from "./logic";
import type { Comment } from "./types";

type ReplyHandler = (body: string) => Promise<{ error: string | null }>;

/**
 * The one card every take renders with — yours and everyone else's. A take
 * is a comment plus whatever extra content the caller passes as `children`
 * (a revealed pick ticket after lock, for example). Replies nest one level
 * under a take, matching what prompts.post_comment (0102) allows: `onReply`
 * is omitted for a reply itself, so a reply's own row never grows a second
 * composer.
 */
export function TakeCard({
  comment,
  isYou = false,
  avatarUrl = null,
  onReply,
  children,
  footer,
  collapsedByDefault = false,
}: {
  comment: Comment;
  isYou?: boolean;
  /** Only ever passed for the viewer's own card — other authors' avatars aren't fetched. */
  avatarUrl?: string | null;
  onReply?: ReplyHandler;
  children?: ReactNode;
  footer?: ReactNode;
  /** Other people's pick tickets stay skim-friendly until the reader asks to open one. */
  collapsedByDefault?: boolean;
}) {
  const [takeExpanded, setTakeExpanded] = useState(!collapsedByDefault);
  const [repliesExpanded, setRepliesExpanded] = useState(false);
  const hasReplies = comment.replies.length > 0;
  const canToggle = hasReplies || Boolean(onReply);
  const canCollapseTake = collapsedByDefault && Boolean(children);

  return (
    <article className={`relative border bg-surface-raised shadow-[0_10px_24px_rgb(0_0_0/0.28)] ${isYou ? "border-fg/25 shadow-[0_10px_26px_rgb(0_0_0/0.42)]" : "border-line"}`}>
      <div className="flex items-center gap-2.5 px-4 pt-4">
        <Avatar name={comment.author} headshotUrl={avatarUrl} />
        <span className="min-w-0 truncate font-semibold text-fg">{comment.author}</span>
        {isYou ? <span className="shrink-0 bg-panel px-1.5 py-0.5 font-mono text-[10px] tracking-[0.06em] text-panel-fg uppercase">You</span> : null}
        <span className="ml-auto shrink-0 font-mono text-[10px] tracking-[0.04em] text-fg-muted">{relativeTime(comment.createdAt)}</span>
      </div>
      {comment.body ? <p className="px-4 pt-3 text-[15px] leading-6 text-fg">{comment.body}</p> : null}
      {takeExpanded ? children : null}
      {!takeExpanded ? (
        <div className="mt-3 border-t border-line px-4 py-3">
          <button
            type="button"
            onClick={() => setTakeExpanded(true)}
            aria-expanded={false}
            className="inline-flex items-center gap-1.5 font-mono text-[10px] tracking-[0.08em] text-fg-muted uppercase hover:text-fg"
          >
            <ChevronDown className="h-3.5 w-3.5" /> View take
          </button>
        </div>
      ) : canCollapseTake || canToggle || footer ? (
        <div className="mt-3 flex items-center gap-4 border-t border-line px-4 py-3">
          {canCollapseTake ? (
            <button
              type="button"
              onClick={() => setTakeExpanded(false)}
              aria-expanded={true}
              className="inline-flex items-center gap-1.5 font-mono text-[10px] tracking-[0.08em] text-fg-muted uppercase hover:text-fg"
            >
              <ChevronUp className="h-3.5 w-3.5" /> Hide take
            </button>
          ) : null}
          {canToggle ? (
            <button
              type="button"
              onClick={() => setRepliesExpanded((value) => !value)}
              aria-expanded={repliesExpanded}
              className="inline-flex items-center gap-1.5 font-mono text-[10px] tracking-[0.08em] text-fg-muted uppercase hover:text-fg"
            >
              {repliesExpanded ? <ChevronUp className="h-3.5 w-3.5" /> : <ChevronDown className="h-3.5 w-3.5" />}
              {hasReplies ? `${comment.replies.length} ${comment.replies.length === 1 ? "reply" : "replies"}` : "Reply"}
            </button>
          ) : null}
          {footer ? <span className="ml-auto">{footer}</span> : null}
        </div>
      ) : null}
      {takeExpanded && repliesExpanded ? (
        <div className="border-t border-line px-4 py-4">
          {hasReplies ? (
            <div className="flex flex-col gap-3 pl-1">
              {comment.replies.map((reply) => (
                <div key={reply.id} className="flex gap-2.5">
                  <Avatar name={reply.author} className="h-7 w-7" />
                  <div className="min-w-0">
                    <p className="text-sm font-semibold text-fg">
                      {reply.author}
                      {reply.isViewer ? <span className="ml-1.5 font-mono text-[9px] tracking-[0.06em] text-fg-muted uppercase">You</span> : null}
                    </p>
                    <p className="mt-0.5 text-sm leading-5 text-fg-muted">{reply.body}</p>
                  </div>
                </div>
              ))}
            </div>
          ) : null}
          {onReply ? <ReplyComposer onReply={onReply} hasReplies={hasReplies} /> : null}
        </div>
      ) : null}
    </article>
  );
}

function ReplyComposer({ onReply, hasReplies }: { onReply: ReplyHandler; hasReplies: boolean }) {
  const [body, setBody] = useState("");
  const [pending, setPending] = useState(false);
  const [error, setError] = useState<string | null>(null);

  async function submit() {
    const trimmed = body.trim();
    if (!trimmed || pending) return;
    setPending(true);
    setError(null);
    const result = await onReply(trimmed);
    setPending(false);
    if (result.error) {
      setError(result.error);
      return;
    }
    setBody("");
  }

  return (
    <div className={hasReplies ? "mt-4 flex flex-col gap-2" : "flex flex-col gap-2"}>
      <div className="flex items-center gap-2">
        <input
          type="text"
          value={body}
          onChange={(event) => setBody(event.target.value)}
          onKeyDown={(event) => {
            if (event.key === "Enter") submit();
          }}
          maxLength={280}
          placeholder="Write a reply…"
          aria-label="Write a reply"
          className="min-w-0 flex-1 border border-line bg-surface px-3 py-2 text-sm text-fg placeholder:text-fg-muted focus:border-fg focus:outline-none"
        />
        <Button variant="ghost" fullWidth={false} disabled={pending || !body.trim()} onClick={submit} className="!min-h-9 !px-3 !text-[11px]">
          {pending ? "Sending…" : "Reply"}
        </Button>
      </div>
      {error ? <p role="alert" className="font-mono text-[10px] tracking-[0.1em] text-grade-rough uppercase">{error}</p> : null}
    </div>
  );
}

function Avatar({ name, headshotUrl, className = "h-9 w-9" }: { name: string; headshotUrl?: string | null; className?: string }) {
  const [failed, setFailed] = useState(false);
  const showImage = Boolean(headshotUrl) && !failed;
  return (
    <span className={`inline-flex shrink-0 items-center justify-center overflow-hidden rounded-full bg-panel-fg font-slab text-panel ${className}`}>
      {showImage ? (
        // Other comment authors' avatars aren't fetched at all (feed.ts only
        // selects display_name for them) — this only ever fires for `isYou`.
        // eslint-disable-next-line @next/next/no-img-element
        <img src={headshotUrl!} alt="" className="h-full w-full object-cover object-top" onError={() => setFailed(true)} />
      ) : (
        initials(name)
      )}
    </span>
  );
}
