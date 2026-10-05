"use client";

import { Lock } from "lucide-react";
import Link from "next/link";
import { useRouter } from "next/navigation";
import { useEffect, useRef, useState } from "react";

import { Button } from "@/components/foundation/ui-kit/Button";
import { AuthorIdentity } from "./AuthorIdentity";
import { BoldQuote } from "./BoldQuote";
import { BoldTagPicker } from "./BoldTagPicker";
import { usePromptDeadlineNow } from "./usePromptDeadline";
import {
  BOLD_BODY_MAX,
  MAX_BOLD_PREDICTIONS,
  submitBoldPredictions,
  type BoldPrediction,
  type BoldPredictionBoardData,
  type BoldTarget,
} from "@/lib/foundation/content/prompts/boldPredictions";
import { isPromptOpenForAnswers } from "@/lib/foundation/content/prompts/logic";
import type { PlayerResult, PlayerSearch } from "@/lib/foundation/content/prompts/players";
import type { Post } from "@/lib/foundation/content/prompts/types";
import { createClient } from "@/lib/supabase/client";

type Draft = { body: string; target: BoldTarget };

export type BoldPredictionActions = {
  submit: (input: { postId: string; predictions: Draft[] }) => Promise<{ error: string | null }>;
};

/** Talks to prompts.* straight from the browser, like TakeComposer does for a response. */
function browserActions(): BoldPredictionActions {
  let client: ReturnType<typeof createClient> | null = null;
  return { submit: (input) => submitBoldPredictions(client ?? (client = createClient()), input) };
}

type TagData = Pick<BoldPredictionBoardData, "weekGames" | "players">;

type Props = {
  post: Post;
  data: BoldPredictionBoardData;
  viewerCanAnswer: boolean;
  displayName?: string;
  avatarUrl?: string | null;
  /** Overrides the write and the player search, for tests. */
  actions?: BoldPredictionActions;
  playerSearch?: PlayerSearch;
};

/**
 * A Bold Predictions post's whole detail surface, shaped like every other
 * prompt: write up to five predictions, lock them in as one response, and
 * that response is final. Locking in is what unlocks everyone else's
 * predictions; after the post locks they are open to all.
 */
export function BoldPredictionsBoard({ post, data, viewerCanAnswer, displayName = "You", avatarUrl = null, actions, playerSearch }: Props) {
  const router = useRouter();
  const now = usePromptDeadlineNow(post);
  const open = isPromptOpenForAnswers(post, now);
  const answered = data.predictions.some((prediction) => prediction.isViewer);
  // Players the viewer found this session, so a tag they just chose keeps its name and headshot.
  const [found, setFound] = useState<Record<string, PlayerResult>>({});
  const tagData: TagData = { weekGames: data.weekGames, players: { ...data.players, ...found } };
  const wasOpen = useRef(open);
  const writes = useRef<BoldPredictionActions | null>(null);
  const act = () => actions ?? (writes.current ??= browserActions());

  // The deadline can pass while the page is on screen; ask for the revealed set.
  useEffect(() => {
    if (wasOpen.current && !open) router.refresh();
    wasOpen.current = open;
  }, [open, router]);

  if (open && !answered) {
    return (
      <section aria-label="Your bold predictions" className="mt-5 w-full max-w-[760px] pb-16">
        {viewerCanAnswer ? (
          <PredictionComposer
            post={post}
            data={tagData}
            displayName={displayName}
            avatarUrl={avatarUrl}
            act={act}
            onPlayerFound={(player) => setFound((current) => ({ ...current, [player.id]: player }))}
            playerSearch={playerSearch}
            onSubmitted={() => router.refresh()}
          />
        ) : (
          <p className="border border-dashed border-line bg-surface-raised px-4 py-4 text-sm text-fg-muted">
            <Link href={`/login?next=/prompts/${post.id}`} className="font-semibold text-fg underline">Sign up</Link> to make your bold predictions. Lock yours in to see everyone else&apos;s.
          </p>
        )}
      </section>
    );
  }

  return <RevealedPredictions post={post} predictions={data.predictions} data={tagData} open={open} />;
}

/** Drafts live in the browser until Lock in; only then does anything reach the server. */
function PredictionComposer({ post, data, displayName, avatarUrl, act, onPlayerFound, playerSearch, onSubmitted }: {
  post: Post;
  data: TagData;
  displayName: string;
  avatarUrl: string | null;
  act: () => BoldPredictionActions;
  onPlayerFound: (player: PlayerResult) => void;
  playerSearch?: PlayerSearch;
  onSubmitted: () => void;
}) {
  const [drafts, setDrafts] = useState<Draft[]>([]);
  const [editingIndex, setEditingIndex] = useState<number | null>(null);
  const [pending, setPending] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const full = drafts.length >= MAX_BOLD_PREDICTIONS;

  async function lockIn() {
    setPending(true);
    setError(null);
    const result = await act().submit({ postId: post.id, predictions: drafts });
    setPending(false);
    if (result.error) return setError(result.error);
    onSubmitted();
  }

  return (
    <div className="flex flex-col gap-4">
      <div className="flex items-center justify-between gap-3">
        <h2 className="font-slab text-xl leading-none uppercase">Your predictions</h2>
        <p className="type-label text-fg-muted">{drafts.length} of {MAX_BOLD_PREDICTIONS} used</p>
      </div>
      <p className="flex items-center gap-2 text-sm text-fg-muted"><Lock aria-hidden className="h-3.5 w-3.5 shrink-0" /> Lock them in as one response. You can&apos;t change it after, and you&apos;ll see everyone else&apos;s.</p>

      <div className={`${CARD_SHELL} p-4`}>
        <YouHeader name={displayName} avatarUrl={avatarUrl} />

        {drafts.length ? (
          <ul className="mt-4 flex flex-col gap-3">
            {drafts.map((draft, index) => (
              <li key={index}>
                {editingIndex === index ? (
                  <PredictionForm
                    idSuffix={`draft-${index}`}
                    initial={draft}
                    data={data}
                    onPlayerFound={onPlayerFound}
                    playerSearch={playerSearch}
                    submitLabel="Save changes"
                    onSubmit={(body, target) => {
                      setDrafts((current) => current.map((item, i) => (i === index ? { body, target } : item)));
                      setEditingIndex(null);
                    }}
                    onCancel={() => setEditingIndex(null)}
                  />
                ) : (
                  <BoldQuote
                    body={draft.body}
                    target={draft.target}
                    data={data}
                    actions={
                      <span className="flex gap-3 type-label">
                        <button type="button" onClick={() => setEditingIndex(index)} aria-label={`Edit prediction: ${draft.body}`} className="cursor-pointer underline">Edit</button>
                        <button
                          type="button"
                          onClick={() => { setDrafts((current) => current.filter((_, i) => i !== index)); setEditingIndex(null); }}
                          aria-label={`Remove prediction: ${draft.body}`}
                          className="cursor-pointer text-grade-rough underline"
                        >
                          Remove
                        </button>
                      </span>
                    }
                  />
                )}
              </li>
            ))}
          </ul>
        ) : null}

        {full ? (
          <p className="mt-4 text-sm text-fg-muted">That&apos;s all five. Remove one to add another.</p>
        ) : (
          <div className="mt-4">
            <PredictionForm
              idSuffix="new"
              data={data}
              onPlayerFound={onPlayerFound}
              playerSearch={playerSearch}
              submitLabel="Add prediction"
              submitVariant="ghost"
              onSubmit={(body, target) => { setDrafts((current) => [...current, { body, target }]); setEditingIndex(null); }}
            />
          </div>
        )}

        <div className="mt-3">
          <Button variant="solid" fullWidth disabled={drafts.length === 0 || editingIndex !== null || pending} onClick={() => void lockIn()}>
            {pending ? "Locking in…" : "Lock in"}
          </Button>
        </div>
        {error ? <p role="alert" className="mt-3 type-label text-grade-rough">{error}</p> : null}
      </div>
    </div>
  );
}

const CARD_SHELL = "relative overflow-hidden border border-line bg-surface-raised text-fg shadow-[0_10px_24px_rgb(0_0_0/0.4)]";

/** The post-card header the pick composer uses: who is answering, tagged as the viewer. */
function YouHeader({ name, avatarUrl }: { name: string; avatarUrl: string | null }) {
  return (
    <div className="flex items-center gap-2.5">
      <AuthorIdentity name={name} avatarUrl={avatarUrl} />
      <span className="shrink-0 bg-panel px-1.5 py-0.5 type-label text-panel-fg">You</span>
    </div>
  );
}

/** The text, its counter and the tag picker — shared by adding a draft and editing one. */
function PredictionForm({ idSuffix, initial, data, onPlayerFound, playerSearch, submitLabel, submitVariant = "solid", onSubmit, onCancel }: {
  idSuffix: string;
  initial?: Draft;
  data: TagData;
  onPlayerFound: (player: PlayerResult) => void;
  playerSearch?: PlayerSearch;
  submitLabel: string;
  submitVariant?: "solid" | "ghost";
  onSubmit: (body: string, target: BoldTarget) => void;
  onCancel?: () => void;
}) {
  const [body, setBody] = useState(initial?.body ?? "");
  const [target, setTarget] = useState<BoldTarget | null>(initial?.target ?? null);
  const trimmed = body.trim();
  const ready = trimmed.length > 0 && trimmed.length <= BOLD_BODY_MAX && target !== null;
  const fieldId = `bold-body-${idSuffix}`;

  function submit() {
    if (!ready || !target) return;
    onSubmit(trimmed, target);
    if (!initial) { setBody(""); setTarget(null); }
  }

  return (
    <form onSubmit={(event) => { event.preventDefault(); submit(); }} className="flex flex-col gap-6">
      <div>
        <label htmlFor={fieldId} className="type-label text-fg-muted">Your prediction</label>
        <div className="relative mt-2">
          <textarea
            id={fieldId}
            value={body}
            onChange={(event) => setBody(event.target.value)}
            maxLength={BOLD_BODY_MAX}
            rows={3}
            placeholder="Make your boldest call…"
            className="block w-full resize-none border border-line bg-surface px-3 pt-2 pb-6 text-lg leading-6 text-fg placeholder:text-fg-muted focus:border-fg focus:outline-none"
          />
          <p aria-live="polite" className="pointer-events-none absolute right-3 bottom-1.5 font-mono text-[10px] leading-none tracking-[0.06em] text-fg-muted tabular-nums">{body.length}/{BOLD_BODY_MAX}</p>
        </div>
      </div>
      <div>
        <p className="mb-2 type-label text-fg-muted">Tag — required</p>
        <BoldTagPicker value={target} onChange={setTarget} weekGames={data.weekGames} players={data.players} onPlayerFound={onPlayerFound} search={playerSearch} />
      </div>
      <div className="flex gap-2">
        <Button type="submit" variant={submitVariant} fullWidth disabled={!ready}>{submitLabel}</Button>
        {onCancel ? <Button type="button" variant="ghost" fullWidth={false} onClick={onCancel}>Cancel</Button> : null}
      </div>
    </form>
  );
}

function RevealedPredictions({ post, predictions, data, open }: { post: Post; predictions: BoldPrediction[]; data: TagData; open: boolean }) {
  const groups = byAuthor(predictions);
  const mine = groups.find((group) => group.isViewer);
  const others = groups.filter((group) => !group.isViewer);

  const card = (group: (typeof groups)[number]) => (
    <article key={group.key} aria-label={`${group.author}'s predictions`} className={`${CARD_SHELL} p-4`}>
      <div className="flex items-center gap-2.5">
        <AuthorIdentity name={group.author} />
        {group.isViewer ? <span className="shrink-0 bg-panel px-1.5 py-0.5 type-label text-panel-fg">You</span> : null}
      </div>
      <ul className="mt-4 flex flex-col gap-3">
        {group.predictions.map((prediction) => (
          <li key={prediction.id}><BoldQuote body={prediction.body} target={prediction.target} data={data} /></li>
        ))}
      </ul>
      {open && group.isViewer ? (
        <p className="mt-3 type-label text-fg-muted">Predictions locked in</p>
      ) : null}
    </article>
  );

  // The same shape as a pick prompt's thread: your own card first, then the other takes under a small label.
  return (
    <section aria-label="Revealed predictions" className="mt-5 w-full max-w-[760px] pb-16">
      {predictions.length === 0 ? (
        <p className="border border-dashed border-line bg-surface-raised px-4 py-4 text-sm text-fg-muted">
          {post.status === "void" ? "This post was voided." : "Nobody made a prediction before this locked."}
        </p>
      ) : (
        <div className="flex flex-col gap-5">
          {mine ? card(mine) : null}
          {others.length ? (
            <div className="flex flex-col gap-3" aria-label="Other takes">
              <h2 className="px-1 type-label text-fg-muted">Other takes</h2>
              {others.map(card)}
            </div>
          ) : null}
        </div>
      )}
    </section>
  );
}

/** One response per person: a viewer's predictions sit together on a single card, in first-seen order. */
function byAuthor(predictions: BoldPrediction[]) {
  const groups = new Map<string, { key: string; author: string; isViewer: boolean; predictions: BoldPrediction[] }>();
  for (const prediction of predictions) {
    const key = `${prediction.isViewer ? "me" : "other"}:${prediction.author}`;
    const group = groups.get(key) ?? { key, author: prediction.author, isViewer: prediction.isViewer, predictions: [] };
    group.predictions.push(prediction);
    groups.set(key, group);
  }
  // Your own response leads, like your take does on a pick prompt.
  return [...groups.values()].sort((left, right) => Number(right.isViewer) - Number(left.isViewer));
}
