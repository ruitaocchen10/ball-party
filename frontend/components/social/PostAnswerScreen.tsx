"use client";

import { ChevronLeft } from "lucide-react";
import { useState } from "react";

import { Button } from "@/components/ui/Button";
import { PlayerPortrait, ProtoTeamLogo } from "./ProtoImages";
import { TicketTexture } from "./TicketTexture";
import { GamePickFace, SlotFaceC, YourCalls } from "./SlotFaces";
import { totalPoints } from "./logic";
import type { Post } from "./types";

/**
 * PROTOTYPE UI, REAL DATA. The dedicated screen where a viewer actually
 * makes or reviews their pick(s). This is a plain whole-screen swap driven
 * by local state, not a modal/overlay or a new route. The feed is only a
 * prompt cover; all personal picks and discussion live on this focused view.
 */
export function PostAnswerScreen({
  post,
  displayName,
  avatarUrl,
  pending,
  error,
  onBack,
  onAnswer,
}: {
  post: Post;
  displayName: string;
  avatarUrl: string | null;
  pending: boolean;
  error: string | null;
  onBack: () => void;
  onAnswer: (response: Record<string, string[]>, comment?: string) => void;
}) {
  const [draft, setDraft] = useState<Record<string, string[]>>(post.viewerResponse ?? {});
  const [comment, setComment] = useState("");

  function setSlotResponse(slotId: string, response: string[]) {
    setDraft((prev) => ({ ...prev, [slotId]: response }));
  }

  function slotFilled(slotId: string) {
    const slot = post.slots.find((s) => s.id === slotId)!;
    const r = draft[slotId] ?? [];
    return slot.shape === "pick" ? r.length === 1 : r.length === (slot.pickCount ?? slot.options.length);
  }

  const completedCount = post.slots.filter((slot) => slotFilled(slot.id)).length;
  const ready = completedCount === post.slots.length;
  const canSubmit = post.status === "open" && !post.viewerAnswered;
  const points = totalPoints(post);
  const heroImage = post.slots.flatMap((slot) => slot.options).find((option) => option.headshotUrl)?.headshotUrl;
  const heroTeams = [...new Set(post.slots.flatMap((slot) => slot.options.map((option) => option.teamCode).filter((code): code is string => Boolean(code))))].slice(0, 2);
  const isMultiPick = post.slots.length > 1;
  const viewerTake = post.comments.find((comment) => comment.isViewer && comment.postedWithPick);
  const friendComments = post.comments.filter((comment) => !(comment.isViewer && comment.postedWithPick));
  return (
    <div className="relative mx-auto w-full max-w-[1080px] pb-32">
      <button type="button" onClick={onBack} className="absolute top-5 right-full mr-6 hidden h-11 w-11 items-center justify-center rounded-full border border-fg/25 bg-surface/55 text-fg backdrop-blur-sm hover:bg-surface lg:flex">
        <ChevronLeft className="h-6 w-6" strokeWidth={2.5} />
        <span className="sr-only">Back to feed</span>
      </button>
      <section className="bg-surface">
      <header className="relative min-h-[12rem] overflow-hidden text-fg sm:min-h-[14rem]">
        {isMultiPick ? <TicketTexture pickCount={post.slots.length} /> : heroImage ? (
          // Player image URLs come from NFL's CDN and are not covered by this app's Next Image configuration.
          // eslint-disable-next-line @next/next/no-img-element
          <img src={heroImage} alt="" className="absolute inset-0 h-full w-full object-cover object-top opacity-65" />
        ) : null}
        <div className="absolute inset-0 bg-[linear-gradient(180deg,rgb(17_19_17/0.3),rgb(17_19_17/0.8)_54%,rgb(17_19_17)_100%)]" />
        {!isMultiPick && !heroImage && heroTeams.length ? (
          <div aria-hidden className="absolute right-5 bottom-4 flex -space-x-8 opacity-30 sm:right-8 sm:bottom-6">
            {heroTeams.map((code) => <ProtoTeamLogo key={code} code={code} className="h-32 w-32 sm:h-40 sm:w-40" />)}
          </div>
        ) : null}
        <button type="button" onClick={onBack} className="absolute top-5 left-4 flex h-11 w-11 items-center justify-center rounded-full border border-fg/25 bg-surface/55 text-fg backdrop-blur-sm hover:bg-surface sm:left-6 lg:hidden">
          <ChevronLeft className="h-6 w-6" strokeWidth={2.5} />
          <span className="sr-only">Back to feed</span>
        </button>
        <div className="absolute inset-x-0 bottom-0 px-4 pb-6 sm:px-6 sm:pb-8">
          <p className="mb-2 font-mono text-[10px] tracking-[0.14em] text-fg-muted uppercase">{post.templateName}</p>
          <h1 className="max-w-xl font-slab text-4xl leading-[0.95] uppercase sm:text-5xl">{post.promptText}</h1>
          <p className="mt-3 max-w-xl text-sm leading-5 text-fg-muted sm:text-base">{post.caption}</p>
        </div>
      </header>

      <div className="grid gap-10 px-4 pt-7 pb-7 sm:px-6 lg:grid-cols-[minmax(0,1.3fr)_minmax(17rem,0.7fr)] lg:gap-12">
        <section aria-label="Your take">
          <h2 className="mb-4 font-slab text-3xl leading-none text-fg uppercase">Your take</h2>
          <div className="overflow-hidden border border-line bg-surface-raised text-fg shadow-[0_10px_24px_rgb(0_0_0/0.4)]">
            <div className="flex items-center gap-2.5 px-4 pt-4">
              <PlayerPortrait name={displayName} headshotUrl={avatarUrl} className="h-9 w-9" />
              <span className="font-semibold">{displayName}</span>
              {points !== null ? <span className={`ml-auto grade-scoremark grade-scoremark--standings ${points > 0 ? "grade-scoremark--elite" : "grade-scoremark--rough"}`}>+{points}</span> : null}
            </div>

            {post.viewerAnswered && viewerTake ? <p className="mx-4 mt-4 text-lg leading-7 font-medium text-fg">{viewerTake.body}</p> : null}

            {canSubmit ? (
              <div className="px-4 pt-4">
                <label htmlFor={`prompt-take-${post.id}`} className="font-mono text-[10px] tracking-[0.1em] text-fg-muted uppercase">Add a take <span className="normal-case">(optional)</span></label>
                <textarea
                  id={`prompt-take-${post.id}`}
                  value={comment}
                  onChange={(event) => setComment(event.target.value)}
                  maxLength={280}
                  rows={2}
                  placeholder="What do you think?"
                  className="mt-2 block w-full resize-none border border-line bg-surface px-3 py-2 text-sm leading-5 text-fg placeholder:text-fg-muted focus:border-fg focus:outline-none"
                />
              </div>
            ) : null}

            {canSubmit && post.slots.length > 1 ? <p className="px-4 pt-4 font-mono text-[10px] tracking-[0.1em] text-fg-muted uppercase">{completedCount} of {post.slots.length} picks made</p> : null}

            {canSubmit && isPicksPost(post) && post.slots.length === 1 ? (
              <GamePickFace slot={post.slots[0]} disabled={false} response={draft[post.slots[0].id] ?? []} onChange={(r) => setSlotResponse(post.slots[0].id, r)} />
            ) : canSubmit && isPicksPost(post) ? (
              <div className="flex flex-col gap-6 px-4 pt-5">{post.slots.map((slot) => <div key={slot.id}><p className="mb-1.5 font-mono text-[10px] tracking-[0.08em] text-fg-muted uppercase">{slot.label}</p><GamePickFace slot={slot} disabled={false} response={draft[slot.id] ?? []} onChange={(r) => setSlotResponse(slot.id, r)} /></div>)}</div>
            ) : canSubmit ? (
              <div className="flex flex-col gap-4 px-4 pt-4">{post.slots.map((slot) => <SlotFaceC key={slot.id} slot={slot} disabled={false} response={draft[slot.id] ?? []} onChange={(r) => setSlotResponse(slot.id, r)} allResponses={draft} />)}</div>
            ) : post.viewerAnswered && isPicksPost(post) ? (
              <YourCalls slots={post.slots} responses={post.viewerResponse ?? {}} resolved={post.status === "resolved"} />
            ) : post.viewerAnswered ? (
              <div className="flex flex-col gap-4 px-4 pt-4">{post.slots.map((slot) => <SlotFaceC key={slot.id} slot={slot} disabled response={post.viewerResponse?.[slot.id] ?? []} onChange={() => {}} allResponses={post.viewerResponse ?? {}} />)}</div>
            ) : <p className="px-4 pt-5 text-sm text-fg-muted">You did not make picks for this prompt.</p>}
            <div className="h-4" />
          </div>
        </section>
        <aside aria-label="Other takes" className="lg:border-l lg:border-line lg:pl-7">
          <h2 className="font-slab text-3xl leading-none text-fg uppercase">Other takes</h2>
          {friendComments.length ? (
            <div className="mt-5 divide-y divide-line border-t border-line">
              {friendComments.map((comment) => (
                <article key={comment.id} className="py-5 first:pt-4">
                  <p className="text-sm font-semibold text-fg">{comment.author}</p>
                  <p className="mt-2 text-base leading-7 text-fg-muted">{comment.body}</p>
                </article>
              ))}
            </div>
          ) : <p className="mt-4 text-sm text-fg-muted">No other takes yet. Share this prompt to get the conversation going.</p>}
        </aside>
      </div>
      </section>

      {canSubmit ? <div className="fixed inset-x-0 bottom-0 z-20 mx-auto w-full max-w-[1080px] border-t border-line bg-surface px-4 py-3 shadow-[0_-8px_24px_rgb(0_0_0/0.4)] sm:px-6">
        {error ? (
          <p role="alert" className="mb-2 font-mono text-[10px] tracking-[0.1em] text-grade-rough uppercase">
            {error}
          </p>
        ) : null}
        <Button variant="ink" fullWidth disabled={!ready || pending} onClick={() => onAnswer(draft, comment.trim() || undefined)}>
          {pending ? "Locking in…" : "Lock in"}
        </Button>
      </div> : null}
    </div>
  );
}

function isPicksPost(post: Post): boolean {
  return post.templateKind === "picks" || post.templateKind === "game_pick" || post.templateKind === "weekly_picks";
}
