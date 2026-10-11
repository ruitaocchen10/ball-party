"use client";

import { OptionIcon } from "./SlotFaces";
import { usePromptDeadlineNow } from "./usePromptDeadline";
import { WeeklyAwardsResults } from "./WeeklyAwards";
import { isPicksPost, isPromptOpenForAnswers, relativeTime } from "@/lib/foundation/content/prompts/logic";
import type { Post } from "@/lib/foundation/content/prompts/types";

/**
 * The detail page's right rail. Used to duplicate OtherTakes as a second,
 * differently-styled list of the same takes now shown in the thread; carries
 * prompt context instead — what it takes to resolve, where it stands, and
 * (for a single-game pick, the only shape with exactly two options) how the
 * huddle split. It is client-rendered so an open status turns locked at the
 * deadline without requiring the reader to refresh.
 */
export function PromptContext({ post }: { post: Post }) {
  const now = usePromptDeadlineNow(post);
  const singleGameSlot = post.templateKind !== "power_rankings" && (isPicksPost(post) || post.isOpinion) && post.slots.length === 1 ? post.slots[0] : null;
  const split = singleGameSlot ? post.aggregate?.[singleGameSlot.id] : undefined;
  const awardsResults = post.templateKind === "weekly_awards" && post.aggregate;
  const consensusSlot = post.templateKind === "power_rankings" ? post.slots[0] : null;
  const consensusTopFive = post.powerRankingTopFive ?? [];

  return (
    <aside aria-label="About this prompt" className="xl:sticky xl:top-[92px] xl:self-start">
      <div className="rounded-card border border-line bg-surface-raised p-4 shadow-well">
        <p className="type-label font-semibold text-hidden-text">Prompt details</p>
        <h2 className="mt-1 font-slab text-[27px] leading-none text-fg uppercase">About this prompt</h2>
        <div className="mt-4 border-t border-line">
          <div className="border-b border-line py-3.5">
            <p className="type-label text-fg-muted">Resolves</p>
            <p className="mt-1.5 text-sm leading-6 text-fg">{post.resolutionCriteria}</p>
          </div>
          <div className={split || consensusTopFive.length || awardsResults ? "border-b border-line py-3.5" : "py-3.5"}>
            <p className="type-label text-fg-muted">Status</p>
            <p className="mt-1.5 text-sm leading-6 text-fg">{statusLine(post, now)}</p>
          </div>
          {singleGameSlot && split ? (
            <div className="py-3.5">
              <div className="flex flex-col gap-2">
                {singleGameSlot.options.map((option) => (
                  <div key={option.id} className="flex items-center gap-2">
                    <OptionIcon option={option} className="h-6 w-6" />
                    <span className="min-w-0 flex-1 truncate font-slab text-sm uppercase">{option.label}</span>
                    <span className="font-mono text-xs text-fg-muted tabular-nums">{split[option.id] ?? 0}%</span>
                  </div>
                ))}
              </div>
              <div className="mt-2.5 flex h-2 overflow-hidden rounded-full border border-line">
                {singleGameSlot.options.map((option) => (
                  <span key={option.id} style={{ width: `${split[option.id] ?? 0}%` }} className="h-full bg-fg first:bg-fg last:bg-fg-muted/40" />
                ))}
              </div>
            </div>
          ) : null}
          {awardsResults ? (
            <div className="py-3.5">
              <WeeklyAwardsResults post={post} />
            </div>
          ) : null}
          {consensusSlot && consensusTopFive.length ? (
            <div className="py-3.5">
              <p className="mb-2.5 type-label text-fg-muted">Most common top 5</p>
              <div className="flex flex-col gap-2">
                {consensusTopFive.map((team, index) => {
                  const option = consensusSlot.options.find((candidate) => candidate.id === team.optionId);
                  if (!option) return null;
                  const percent = post.responseCount ? Math.round((team.topFiveCount / post.responseCount) * 100) : 0;
                  return (
                    <div key={team.optionId} className="flex items-center gap-2">
                      <span className="w-4 font-slab text-lg leading-none text-fg-muted tabular-nums">{index + 1}</span>
                      <OptionIcon option={option} className="h-6 w-6" />
                      <span className="min-w-0 flex-1 truncate font-slab text-sm uppercase">{option.label}</span>
                      <span className="font-mono text-xs text-fg-muted tabular-nums">{percent}%</span>
                    </div>
                  );
                })}
              </div>
            </div>
          ) : null}
        </div>
      </div>
    </aside>
  );
}

function statusLine(post: Post, now: number): string {
  const people = post.templateKind === "bold_predictions"
    ? `${post.predictionCount ?? 0} ${post.predictionCount === 1 ? "prediction" : "predictions"}`
    : `${post.responseCount} ${post.responseCount === 1 ? "person" : "people"} answered`;
  if (post.status === "void") return `Voided — ${post.voidReason ?? "no reason given"}`;
  if (post.status === "resolved") return `Resolved · ${people}`;
  if (!isPromptOpenForAnswers(post, now)) return `Locked · ${people}`;
  return `Open · closes ${relativeTime(post.lockAt)}`;
}
