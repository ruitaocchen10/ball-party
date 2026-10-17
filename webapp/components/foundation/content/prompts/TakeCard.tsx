"use client";

import { MessageCircle } from "lucide-react";
import Link from "next/link";
import { type ReactNode, useState } from "react";

import { ReportTakeButton } from "@/components/foundation/moderation/ReportButton";
import { AuthorIdentity } from "./AuthorIdentity";
import { TakeBallVote } from "./TakeBallVote";
import { relativeTime } from "@/lib/foundation/content/prompts/logic";
import type { Comment } from "@/lib/foundation/content/prompts/types";
import { Badge } from "@/components/foundation/ui-kit/Badge";

/**
 * A compact take preview. Discussion lives on its own take-thread route so
 * the feed can prioritize the author's call and comment over reply controls.
 */
export function TakeCard({
  comment,
  isYou = false,
  avatarUrl = null,
  commentHref,
  children,
  footer,
  composer,
  thread,
  collapsedByDefault = false,
  expandedByDefault = false,
  replyCount,
  context,
}: {
  comment: Comment;
  isYou?: boolean;
  /** Overrides the author's own picture, which comes with the comment. */
  avatarUrl?: string | null;
  /** A real comment id is required to open the discussion for this take. */
  commentHref?: string;
  children?: ReactNode;
  footer?: ReactNode;
  /** An optional inline reply control, visually attached beneath the card actions. */
  composer?: ReactNode;
  /** Discussion content attached beneath the take and its reply control. */
  thread?: ReactNode;
  /** Other people's pick tickets stay skim-friendly until the reader asks to open one. */
  collapsedByDefault?: boolean;
  /** Foldable like the others, but starts open: the viewer's own take on the prompt page. */
  expandedByDefault?: boolean;
  /** For a take whose replies aren't loaded: the count to show instead of `comment.replies.length`. */
  replyCount?: number;
  /** Sits between the author line and the take: what the take is answering (the friends feed's prompt strip). */
  context?: ReactNode;
}) {
  const [takeExpanded, setTakeExpanded] = useState(!collapsedByDefault || expandedByDefault);
  const canCollapseTake = (collapsedByDefault || expandedByDefault) && Boolean(children);
  const canReport = !isYou && Boolean(comment.id) && Boolean(comment.body.trim());
  const hasBottomRow = Boolean(comment.reaction || commentHref || canCollapseTake || footer || canReport);

  return (
    <article className="relative rounded-card border border-line bg-surface-raised shadow-[0_10px_24px_rgb(0_0_0/0.4)]">
      <div className="flex items-center gap-2.5 px-4 pt-4">
        <AuthorIdentity name={comment.author} avatarUrl={avatarUrl ?? comment.authorAvatarUrl ?? null} username={comment.authorUsername} />
        {isYou ? <Badge>You</Badge> : null}
        <span className="ml-auto shrink-0 font-mono text-[10px] tracking-[0.04em] text-fg-muted">{relativeTime(comment.createdAt)}</span>
      </div>
      {context ? <div className="px-4 pt-3">{context}</div> : null}
      {comment.body ? <p className={`px-4 pt-4 text-lg leading-7 font-medium text-fg${hasBottomRow || children ? "" : " pb-4"}`}>{comment.body}</p> : null}
      {takeExpanded ? children : null}
      {/* No bottom row (a take with no comment link or footer, as in the friends feed): pad under the picks. */}
      {takeExpanded && children && !hasBottomRow ? <div className="pb-4" /> : null}
      {hasBottomRow ? (
        <div className="flex items-center gap-3 px-4 pt-4 pb-4">
          {comment.reaction ? <TakeBallVote takeId={comment.id} initial={comment.reaction} /> : null}
          {commentHref ? (
            <Link href={commentHref} aria-label={`Comment on ${comment.author}'s take`} className="inline-flex items-center gap-1.5 text-fg-muted transition-colors hover:text-fg">
              <MessageCircle className="h-5 w-5" strokeWidth={1.8} />
              {(replyCount ?? comment.replies.length) ? <span className="font-mono text-xs">{replyCount ?? comment.replies.length}</span> : null}
            </Link>
          ) : null}
          {footer ? <span className="min-w-0">{footer}</span> : null}
          {canReport ? <ReportTakeButton takeId={comment.id} authorName={comment.author} /> : null}
          {canCollapseTake ? (
            <button
              type="button"
              onClick={() => setTakeExpanded((expanded) => !expanded)}
              aria-expanded={takeExpanded}
              className="ml-auto inline-flex items-center gap-1.5 type-label text-fg-muted hover:text-fg"
            >
              {takeExpanded ? "Hide take" : "View take"}
            </button>
          ) : null}
        </div>
      ) : null}
      {composer ? <div className="border-t border-line px-4 py-4">{composer}</div> : null}
      {thread ? <div className="border-t border-line">{thread}</div> : null}
    </article>
  );
}
