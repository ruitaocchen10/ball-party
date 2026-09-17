"use client";

import { Check, ChevronDown, ChevronLeft, ChevronRight, ChevronUp } from "lucide-react";
import Link from "next/link";
import { useEffect, useState, type ReactNode } from "react";

import { Button } from "@/components/foundation/ui-kit/Button";
import { Card } from "@/components/foundation/ui-kit/Card";
import { Select } from "@/components/foundation/ui-kit/Select";
import type { NflScheduleGame } from "@/lib/foundation/content/nfl/schedule";
import { OptionIcon } from "./SlotFaces";
import { MatchupPicker } from "./MatchupPicker";
import {
  CheckboxPoolField,
  GameSelectField,
  TEMPLATE_DEFS,
  buildCustomMultiSlots,
  buildGamePickSlots,
  buildRankingSlots,
  buildStatLeaderSlots,
  defaultCriteria,
  defaultPromptText,
  optionPoolFor,
} from "./ComposerFields";
import { isPicksPost, relativeTime } from "@/lib/foundation/content/prompts/logic";
import type { MatchupGameContext, Option, Player, Post, Slot, TemplateKind } from "@/lib/foundation/content/prompts/types";

/**
 * Big match-style tiles borrowing this app's own
 * hidden/revealed drama (the grade-scoremark reveal) instead of a generic
 * social-card look — the shape that won out over the other two feed layouts
 * this started as (see the directory's git history). The feed (PromptPostFeed,
 * mounted on Home) and the composer (PromptPostComposer, mounted at
 * /admin/prompts) are two separate pages — regular users get no compose
 * entry point at all.
 *
 * Answering a post is its own route workspace, not something this
 * card does inline — see PromptFeedShell for the feed ⟷ detail-screen
 * swap. PostCardC is deliberately only a prompt cover: enough matchup context
 * to invite a response, while picks and takes stay behind the post tap.
 */
export function PromptPostFeed({
  posts,
  viewerCanAnswer,
  onSelectPost,
  gameContexts = [],
  home = false,
}: {
  posts: Post[];
  viewerCanAnswer: boolean;
  onSelectPost: (postId: string) => void;
  gameContexts?: MatchupGameContext[];
  /** Home supplies the Huddle heading and its narrower dashboard column. */
  home?: boolean;
}) {
  return (
    <div className={home ? "mt-5 w-full max-w-[760px] pb-16" : "mx-auto w-full max-w-2xl px-4 pt-8 pb-16 sm:px-6"}>
      {home ? null : <h1 className="mb-5 font-slab text-2xl leading-none uppercase">This week</h1>}
      <div className="flex flex-col gap-5">
        {posts.map((post) => (
          <PostCardC key={post.id} post={post} viewerCanAnswer={viewerCanAnswer} onOpenAnswer={() => onSelectPost(post.id)} gameContexts={gameContexts} />
        ))}
      </div>
    </div>
  );
}

function PostCardC({
  post,
  viewerCanAnswer,
  onOpenAnswer,
  gameContexts = [],
}: {
  post: Post;
  viewerCanAnswer: boolean;
  onOpenAnswer: () => void;
  gameContexts?: MatchupGameContext[];
}) {
  const canAnswer = post.status === "open" && !post.viewerAnswered;
  const void_ = post.status === "void";
  const actionLabel = canAnswer ? "Make your picks" : post.viewerAnswered && post.status === "open" ? "View your picks" : "See takes";
  const timingLabel = usePostTimingLabel(post);

  return (
    <Card edge={false} className={`rounded-none border border-line !bg-surface-raised !text-fg !shadow-[0_10px_24px_rgb(0_0_0/0.4)] ${void_ ? "opacity-45" : ""}`}>
      <div className="flex items-start gap-3 px-4 pt-4">
        <h2 className="min-w-0 flex-1 font-slab text-2xl leading-[1.05] uppercase">{post.promptText}</h2>
        <span className="shrink-0 pt-0.5 font-mono text-[10px] tracking-[0.14em] text-fg-muted uppercase">{timingLabel}</span>
      </div>
      <p className="px-4 pt-1 text-[13px] text-fg-muted">{post.caption}</p>

      {void_ ? (
        <p className="mx-4 mt-3 flex items-center gap-2 bg-surface px-3 py-2 font-mono text-[10px] tracking-[0.08em] text-fg-muted uppercase">
          {post.voidReason}
        </p>
      ) : null}

      <PostTeaser post={post} gameContexts={gameContexts} />
      <div className="flex items-center justify-between gap-3 px-4 pt-4">
        <p className="font-mono text-[10px] tracking-[0.1em] text-fg-muted uppercase">
          {post.responseCount} {post.responseCount === 1 ? "person has" : "people have"} answered
        </p>
        {post.status === "locked" ? <span className="font-mono text-[9px] tracking-[0.1em] text-fg-muted uppercase">Locked</span> : null}
      </div>
      <div className="px-4 pt-3 pb-4">
        {canAnswer && !viewerCanAnswer ? (
          <Link href="/login?next=/" className="flex h-12 items-center justify-center bg-panel px-4 font-slab text-[15px] tracking-[0.04em] text-panel-fg uppercase hover:bg-[#fffdf7]">
            Sign up to answer
          </Link>
        ) : (
          <Button variant="solid" fullWidth onClick={onOpenAnswer}>{actionLabel}</Button>
        )}
      </div>
    </Card>
  );
}

/** Refreshes open prompts once per minute so their close countdown stays honest without a live subscription. */
function usePostTimingLabel(post: Post) {
  const [now, setNow] = useState(() => Date.now());
  const closesAt = new Date(post.lockAt).getTime();
  const countingDown = post.status === "open" && Number.isFinite(closesAt) && closesAt > now;

  useEffect(() => {
    if (!countingDown) return;
    const interval = window.setInterval(() => setNow(Date.now()), 60_000);
    return () => window.clearInterval(interval);
  }, [countingDown]);

  return countingDown ? `Closes ${relativeTime(post.lockAt)}` : relativeTime(post.createdAt);
}

/**
 * A non-interactive teaser for an open, unanswered post. A single matchup is
 * a game-poster cover; a set puts that same cover in a compact carousel.
 */
function PostTeaser({ post, gameContexts }: { post: Post; gameContexts: MatchupGameContext[] }) {
  if (isPicksPost(post) && post.slots.length === 1) {
    const slot = post.slots[0];
    return <div className="mx-4 mt-4"><MatchupPicker slot={slot} context={gameContexts.find((game) => game.id === slot.sourceGameId)} testId="single-game-matchup-preview" variant="featured" mode="preview" /></div>;
  }

  if (isPicksPost(post)) {
    return <WeeklyMatchupCarousel post={post} gameContexts={gameContexts} />;
  }

  const allOptions = post.slots.flatMap((slot) => slot.options);
  const options = [...new Map(allOptions.map((option) => [option.id, option])).values()];
  const shown = options.slice(0, 6);
  const overflow = options.length - shown.length;

  return (
    <div className="mt-3 flex flex-col items-center gap-2 px-4">
      {post.slots.length > 1 ? (
        <p className="font-mono text-[10px] tracking-[0.1em] text-fg-muted uppercase">{post.slots.length} picks to make</p>
      ) : null}
      <div className="flex items-center gap-2">
        {shown.map((option) => (
          <OptionIcon key={option.id} option={option} className="h-8 w-8" />
        ))}
        {overflow > 0 ? (
          <span className="flex h-8 w-8 items-center justify-center rounded-full bg-surface font-mono text-[10px] text-fg-muted">+{overflow}</span>
        ) : null}
      </div>
    </div>
  );
}

function WeeklyMatchupCarousel({ post, gameContexts }: { post: Post; gameContexts: MatchupGameContext[] }) {
  const [activeIndex, setActiveIndex] = useState(0);
  const slot = post.slots[activeIndex];
  const total = post.slots.length;
  const goTo = (index: number) => setActiveIndex((index + total) % total);

  return (
    <section data-testid="multi-game-matchup-preview" aria-label={`${post.templateName} matchup carousel`} className="mx-4 mt-4">
      <MatchupPicker slot={slot} context={gameContexts.find((game) => game.id === slot.sourceGameId)} variant="featured" mode="preview" />
      <div className="mt-2 flex items-center justify-between gap-3 px-1">
        <button type="button" onClick={() => goTo(activeIndex - 1)} aria-label="Previous matchup" className="flex h-8 w-8 items-center justify-center border border-line bg-surface text-fg transition-colors hover:bg-surface-raised focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-panel">
          <ChevronLeft className="h-4 w-4" strokeWidth={2} />
        </button>
        <div className="flex items-center gap-1.5" aria-label={`Showing matchup ${activeIndex + 1} of ${total}`}>
          {post.slots.map((matchup, index) => (
            <button key={matchup.id} type="button" onClick={() => goTo(index)} aria-label={`Show matchup ${index + 1}`} aria-current={index === activeIndex ? "true" : undefined} className={`h-1.5 transition-[width,background-color] ${index === activeIndex ? "w-6 bg-panel" : "w-1.5 bg-line hover:bg-fg-muted"}`} />
          ))}
        </div>
        <button type="button" onClick={() => goTo(activeIndex + 1)} aria-label="Next matchup" className="flex h-8 w-8 items-center justify-center border border-line bg-surface text-fg transition-colors hover:bg-surface-raised focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-panel">
          <ChevronRight className="h-4 w-4" strokeWidth={2} />
        </button>
      </div>
    </section>
  );
}

/** `datetime-local` needs `YYYY-MM-DDTHH:mm` in the browser's own timezone — Date#toISOString is UTC and won't round-trip into the input. */
function toLocalInputValue(d: Date): string {
  const pad = (n: number) => String(n).padStart(2, "0");
  return `${d.getFullYear()}-${pad(d.getMonth() + 1)}-${pad(d.getDate())}T${pad(d.getHours())}:${pad(d.getMinutes())}`;
}

function defaultLockAt(): string {
  return toLocalInputValue(new Date(Date.now() + 2 * 24 * 3600_000));
}

/** Wrapped rather than inlined so the `Date.now()` read doesn't happen directly in a component body — see logic.ts's relativeTime for the same shape. */
function isInPast(localDateTime: string): boolean {
  const ms = new Date(localDateTime).getTime();
  return Number.isNaN(ms) || ms <= Date.now();
}

export type CreatePromptPostParams = {
  templateKind: TemplateKind;
  templateName: string;
  caption: string;
  promptText: string;
  resolutionCriteria: string;
  lockAt: string;
  slots: Slot[];
  resolutionSource?: { provider: "nflverse"; rule: "winner" };
  isOpinion?: boolean;
};

const OPINION_CRITERIA = "Opinion only — there's no correct answer, so no points are awarded. Just for the debate.";

export function PromptPostComposer({
  displayName,
  games,
  players,
  onPublish,
}: {
  displayName: string;
  games: NflScheduleGame[];
  players: Player[];
  onPublish: (params: CreatePromptPostParams) => Promise<{ error: string } | { id: string }>;
}) {
  // `games.csv` contains past seasons too. Start at the first unplayed game
  // rather than making the compose screen open on the oldest archived one.
  const initialGame = games.find((game) => !isInPast(game.kickoff)) ?? games.at(-1);
  const [dockOpen, setDockOpen] = useState(true);
  const [published, setPublished] = useState(false);
  const [pending, setPending] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [kind, setKind] = useState<TemplateKind>("picks");
  const [isOpinion, setIsOpinion] = useState(false);
  const [picksMode, setPicksMode] = useState<"single" | "set">("single");
  const [gameId, setGameId] = useState(initialGame?.id ?? "");
  const [season, setSeason] = useState(String(initialGame?.season ?? ""));
  const [week, setWeek] = useState(String(initialGame?.week ?? ""));
  const [weeklyGameIds, setWeeklyGameIds] = useState<string[]>([]);
  const [playerIds, setPlayerIds] = useState<string[]>([]);
  const [playerPosition, setPlayerPosition] = useState("all");
  const [playerSearch, setPlayerSearch] = useState("");
  const [rankingTarget, setRankingTarget] = useState<"teams" | "players" | "games">("teams");
  const [rankingIds, setRankingIds] = useState<string[]>([]);
  const [rankCount, setRankCount] = useState(1);
  const [caption, setCaption] = useState("");
  const [promptText, setPromptText] = useState(defaultPromptText("picks", initialGame));
  const [criteria, setCriteria] = useState(defaultCriteria("picks"));
  const [lockAt, setLockAt] = useState(defaultLockAt);

  function pickTemplate(next: TemplateKind) {
    setKind(next);
    if (next === "picks") {
      selectSchedulePeriod(season, week, next, picksMode);
    } else {
      setPromptText(defaultPromptText(next, games.find((game) => game.id === gameId)));
    }
    setCriteria(isOpinion ? OPINION_CRITERIA : defaultCriteria(next));
  }

  function toggleOpinion() {
    const next = !isOpinion;
    setIsOpinion(next);
    setCriteria(next ? OPINION_CRITERIA : defaultCriteria(kind));
  }

  const selectedGame = games.find((game) => game.id === gameId);
  const seasons = [...new Set(games.map((game) => game.season))].sort((left, right) => right - left);
  const weeks = [...new Set(games.filter((game) => String(game.season) === season).map((game) => game.week))].sort((left, right) => left - right);
  const weeklyGames = games.filter((game) => String(game.season) === season && String(game.week) === week);
  const firstWeekForSeason = (nextSeason: string) => String(
    [...new Set(games.filter((game) => game.season === Number(nextSeason)).map((game) => game.week))].sort((left, right) => left - right)[0] ?? "",
  );

  function selectSchedulePeriod(nextSeason: string, nextWeek: string, template = kind, mode = picksMode) {
    const nextGames = games.filter((game) => String(game.season) === nextSeason && String(game.week) === nextWeek);
    setSeason(nextSeason);
    setWeek(nextWeek);
    setGameId(nextGames[0]?.id ?? "");
    setWeeklyGameIds(nextGames.map((game) => game.id));
    setPromptText(defaultPromptText(template, nextGames[0], mode));
  }

  const allPlayerOptions = players.map((player) => ({
    id: player.id,
    label: player.name,
    sublabel: `${player.position} · ${player.team}`,
    headshotUrl: player.headshotUrl || undefined,
    teamCode: player.team,
    position: player.position,
  }));
  const playerOptions = allPlayerOptions.filter((player) =>
    (playerPosition === "all" || player.position === playerPosition || (playerPosition === "other" && !["QB", "RB", "WR", "TE"].includes(player.position)))
    && `${player.label} ${player.sublabel}`.toLowerCase().includes(playerSearch.trim().toLowerCase()),
  );
  const rankingOptions = rankingTarget === "teams"
    ? optionPoolFor("ranking")
    : rankingTarget === "players"
      ? allPlayerOptions
      : weeklyGames.map((game) => ({
          id: game.id,
          label: game.label,
          sublabel: new Date(game.kickoff).toLocaleString(),
          teamCodes: [game.away, game.home],
        }));
  const effectiveRankCount = Math.min(rankCount, rankingIds.length);
  const visibleRankingOptions = rankingTarget === "players" ? playerOptions : rankingOptions;

  const slots =
    kind === "picks"
      ? picksMode === "single"
        ? selectedGame ? buildGamePickSlots(selectedGame) : []
        : weeklyGames.filter((game) => weeklyGameIds.includes(game.id)).flatMap(buildGamePickSlots)
      : kind === "stat_leader"
        ? buildStatLeaderSlots(players.filter((p) => playerIds.includes(p.id)))
        : kind === "ranking"
          ? effectiveRankCount > 0
            ? buildRankingSlots(rankingOptions.filter((option) => rankingIds.includes(option.id)), effectiveRankCount)
            : []
          : buildCustomMultiSlots();

  const templateName = TEMPLATE_DEFS.find((t) => t.kind === kind)!.name;
  const lockAtDate = new Date(lockAt);
  const lockInPast = isInPast(lockAt);
  const previewPost: Post = {
    id: "preview",
    templateKind: kind,
    templateName,
    author: displayName,
    caption: caption || "Preview caption",
    createdAt: new Date().toISOString(),
    promptText,
    resolutionCriteria: criteria,
    lockAt: lockInPast ? new Date().toISOString() : lockAtDate.toISOString(),
    status: "open",
    responseCount: 0,
    viewerAnswered: false,
    isOpinion,
    slots,
    comments: [],
  };

  const previewContents = (
    <>
      <PostCardC post={previewPost} viewerCanAnswer onOpenAnswer={() => {}} />
      <div className="mt-3">
        {error ? <p role="alert" className="mb-2 font-mono text-[10px] tracking-[0.1em] text-grade-rough uppercase">{error}</p> : null}
        <Button
          fullWidth
          disabled={pending || lockInPast || slots.length === 0 || (kind === "ranking" && effectiveRankCount === 0)}
          onClick={async () => {
            setPending(true);
            setError(null);
            const result = await onPublish({
              templateKind: kind,
              templateName,
              caption: caption || "Preview caption",
              promptText,
              resolutionCriteria: criteria,
              lockAt: lockAtDate.toISOString(),
              slots,
              isOpinion,
              ...(kind === "picks" && !isOpinion ? { resolutionSource: { provider: "nflverse", rule: "winner" } } : {}),
            });
            setPending(false);
            if ("error" in result) {
              setError(result.error);
              return;
            }
            setPublished(true);
          }}
        >
          {pending ? "Publishing…" : "Publish now"}
        </Button>
      </div>
    </>
  );

  if (published) {
    return (
      <div className="mx-auto flex max-w-lg flex-col items-center gap-4 px-4 py-16 text-center">
        <span className="flex h-12 w-12 items-center justify-center rounded-full bg-grade-elite/15 text-grade-elite">
          <Check className="h-6 w-6" strokeWidth={2.5} />
        </span>
        <p className="font-slab text-xl uppercase">Published</p>
        <p className="max-w-[38ch] text-sm text-fg-muted">It&apos;s live on the feed now — players can answer it until it locks.</p>
        <div className="flex gap-2">
          <Button
            variant="ghost"
            onClick={() => {
              setPublished(false);
              setKind("picks");
              setPicksMode("single");
              setCaption("");
              setPlayerIds([]);
              setRankingIds([]);
              setRankCount(1);
              setGameId(initialGame?.id ?? "");
              setWeeklyGameIds([]);
              setPromptText(defaultPromptText("picks", initialGame));
              setCriteria(defaultCriteria("picks"));
              setIsOpinion(false);
              setLockAt(defaultLockAt());
              setError(null);
              setDockOpen(true);
            }}
          >
            Create another
          </Button>
          <Link
            href="/"
            className="flex h-12 items-center bg-panel px-4 font-slab text-[15px] tracking-[0.04em] text-panel-fg uppercase hover:bg-[#fffdf7]"
          >
            View feed
          </Link>
        </div>
      </div>
    );
  }

  return (
    <div className="mx-auto w-full max-w-6xl px-4 pt-8 pb-44 sm:px-6 lg:pb-12">
      <div className="lg:grid lg:grid-cols-[minmax(0,1fr)_minmax(360px,440px)] lg:items-start lg:gap-8 xl:gap-12">
        <div>
          <h1 className="mb-5 font-slab text-2xl leading-none uppercase">New prompt</h1>
          <div className="flex flex-col gap-6">
        <FieldBlock label="Template">
          <div className="flex flex-wrap gap-1.5">
            {TEMPLATE_DEFS.map((t) => (
              <button
                key={t.kind}
                type="button"
                onClick={() => pickTemplate(t.kind)}
                className={`px-3 py-2 font-slab text-xs uppercase ${kind === t.kind ? "bg-panel text-panel-fg" : "bg-surface-raised text-fg-muted ring-1 ring-line ring-inset"}`}
              >
                {t.name}
              </button>
            ))}
          </div>
        </FieldBlock>

        <FieldBlock label="Resolution">
          <button
            type="button"
            onClick={toggleOpinion}
            className={`flex items-center gap-1.5 px-3 py-2 font-slab text-xs uppercase ${isOpinion ? "bg-panel text-panel-fg" : "bg-surface-raised text-fg-muted ring-1 ring-line ring-inset"}`}
          >
            {isOpinion ? <Check className="h-3.5 w-3.5" strokeWidth={2.5} /> : null}
            Opinion — no correct answer, no points
          </button>
        </FieldBlock>

        {kind === "picks" ? (
          <>
            <FieldBlock label="Pick setup">
              <div className="flex flex-wrap gap-1.5">
                {(["single", "set"] as const).map((mode) => (
                  <button
                    key={mode}
                    type="button"
                    onClick={() => {
                      setPicksMode(mode);
                      if (mode === "set") setWeeklyGameIds((current) => current.length ? current : weeklyGames.map((game) => game.id));
                      setPromptText(defaultPromptText("picks", selectedGame ?? weeklyGames[0], mode));
                    }}
                    className={`px-3 py-2 font-slab text-xs uppercase ${picksMode === mode ? "bg-panel text-panel-fg" : "bg-surface-raised text-fg-muted ring-1 ring-line ring-inset"}`}
                  >
                    {mode === "single" ? "One game" : "Set of games"}
                  </button>
                ))}
              </div>
            </FieldBlock>
            <FieldBlock label="Season">
              <Select name="picks-season" ariaLabel="NFL season" value={season} onValueChange={(nextSeason) => selectSchedulePeriod(nextSeason, firstWeekForSeason(nextSeason), "picks")} options={seasons.map((value) => ({ value: String(value), label: String(value) }))} />
            </FieldBlock>
            <FieldBlock label="Week">
              <Select name="picks-week" ariaLabel="NFL week" value={week} onValueChange={(nextWeek) => selectSchedulePeriod(season, nextWeek, "picks")} options={weeks.map((value) => ({ value: String(value), label: `Week ${value}` }))} />
            </FieldBlock>
            {picksMode === "single" ? <FieldBlock label="Game">
              {weeklyGames.length ? <GameSelectField value={gameId} onChange={(id) => {
                setGameId(id);
                setPromptText(defaultPromptText("picks", weeklyGames.find((game) => game.id === id)));
              }} games={weeklyGames} /> : <p className="text-sm text-fg-muted">The NFL schedule is temporarily unavailable. Try again shortly.</p>}
            </FieldBlock> : <FieldBlock label="Games — all selected by default">
              {weeklyGames.length ? <CheckboxPoolField options={weeklyGames.map((game) => ({ id: game.id, label: game.label, sublabel: new Date(game.kickoff).toLocaleString(), teamCodes: [game.away, game.home] }))} selectedIds={weeklyGameIds} onToggle={(id) => setWeeklyGameIds((current) => current.includes(id) ? current.filter((gameId_) => gameId_ !== id) : [...current, id])} roomyTeams /> : <p className="text-sm text-fg-muted">Choose a season and week with scheduled games.</p>}
            </FieldBlock>}
          </>
        ) : null}
        {kind === "stat_leader" ? (
          <PlayerCandidatePicker
            allOptions={allPlayerOptions}
            matchingOptions={playerOptions}
            position={playerPosition}
            search={playerSearch}
            selectedIds={playerIds}
            onPositionChange={setPlayerPosition}
            onSearchChange={setPlayerSearch}
            onToggle={(id) => setPlayerIds((current) => current.includes(id) ? current.filter((value) => value !== id) : [...current, id])}
          />
        ) : null}
        {kind === "ranking" ? (
          <>
            <FieldBlock label="What should people rank?">
              <div className="flex flex-wrap gap-1.5">
                {(["teams", "players", "games"] as const).map((target) => (
                  <button
                    key={target}
                    type="button"
                    onClick={() => { setRankingTarget(target); setRankingIds([]); setRankCount(1); }}
                    className={`px-3 py-2 font-slab text-xs uppercase ${rankingTarget === target ? "bg-panel text-panel-fg" : "bg-surface-raised text-fg-muted ring-1 ring-line ring-inset"}`}
                  >
                    {target}
                  </button>
                ))}
              </div>
            </FieldBlock>
            {rankingTarget === "games" ? (
              <>
                <FieldBlock label="Season">
                  <Select name="ranking-season" ariaLabel="Ranking NFL season" value={season} onValueChange={(nextSeason) => selectSchedulePeriod(nextSeason, firstWeekForSeason(nextSeason), "ranking")} options={seasons.map((value) => ({ value: String(value), label: String(value) }))} />
                </FieldBlock>
                <FieldBlock label="Week">
                  <Select name="ranking-week" ariaLabel="Ranking NFL week" value={week} onValueChange={(nextWeek) => selectSchedulePeriod(season, nextWeek, "ranking")} options={weeks.map((value) => ({ value: String(value), label: `Week ${value}` }))} />
                </FieldBlock>
              </>
            ) : null}
            {rankingTarget === "players" ? (
              <PlayerCandidatePicker
                allOptions={allPlayerOptions}
                matchingOptions={playerOptions}
                position={playerPosition}
                search={playerSearch}
                selectedIds={rankingIds}
                onPositionChange={setPlayerPosition}
                onSearchChange={setPlayerSearch}
                onToggle={(id) => setRankingIds((current) => {
                  const next = current.includes(id) ? current.filter((value) => value !== id) : [...current, id];
                  setRankCount((count) => Math.min(count, Math.max(next.length, 1)));
                  return next;
                })}
              />
            ) : null}
            {rankingTarget !== "players" ? <FieldBlock label={`${rankingTarget[0].toUpperCase()}${rankingTarget.slice(1)} to rank — choose a candidate pool`}>
              <CheckboxPoolField
                options={visibleRankingOptions}
                selectedIds={rankingIds}
                onToggle={(id) => setRankingIds((current) => {
                  const next = current.includes(id) ? current.filter((value) => value !== id) : [...current, id];
                  setRankCount((count) => Math.min(count, Math.max(next.length, 1)));
                  return next;
                })}
                roomyTeams={rankingTarget === "games"}
              />
            </FieldBlock> : null}
            <FieldBlock label="How many should they rank?">
              <input
                type="number"
                min={1}
                max={Math.max(rankingIds.length, 1)}
                value={effectiveRankCount || 1}
                disabled={rankingIds.length === 0}
                onChange={(event) => setRankCount(Math.max(1, Math.min(Number(event.target.value) || 1, rankingIds.length)))}
                className="w-24 rounded border border-line bg-surface-raised px-3 py-2 text-sm disabled:opacity-40"
              />
              <p className="mt-1 text-xs text-fg-muted">People will order their top {effectiveRankCount || "N"} from the {rankingIds.length} candidates you selected.</p>
            </FieldBlock>
          </>
        ) : null}
        {kind === "custom_multi" ? (
          <FieldBlock label="Structure">
            <p className="font-mono text-[11px] leading-[1.6] text-fg-muted">
              4 division-winner picks + a 3-team wildcard set. A team already picked as a division winner is
              excluded from the wildcard pool automatically.
            </p>
          </FieldBlock>
        ) : null}

        <FieldBlock label="Caption">
          <input value={caption} onChange={(e) => setCaption(e.target.value)} className="w-full rounded border border-line bg-surface-raised px-3 py-2 text-sm" />
        </FieldBlock>
        <FieldBlock label="Prompt text">
          <input value={promptText} onChange={(e) => setPromptText(e.target.value)} className="w-full rounded border border-line bg-surface-raised px-3 py-2 text-sm" />
        </FieldBlock>
        <FieldBlock label="Resolution criteria — shown before anyone answers">
          <textarea value={criteria} onChange={(e) => setCriteria(e.target.value)} rows={3} className="w-full rounded border border-line bg-surface-raised px-3 py-2 text-sm" />
        </FieldBlock>
        <FieldBlock label="Locks at">
          <input
            type="datetime-local"
            value={lockAt}
            onChange={(e) => setLockAt(e.target.value)}
            className="w-full rounded border border-line bg-surface-raised px-3 py-2 text-sm"
          />
          {lockInPast ? (
            <p className="mt-1 font-mono text-[9px] tracking-[0.1em] text-grade-rough uppercase">Pick a time in the future</p>
          ) : null}
        </FieldBlock>
          </div>
        </div>

        <aside className="sticky top-6 hidden lg:block">
          <div className="overflow-hidden rounded-card border border-line bg-surface-raised shadow-[0_8px_24px_rgb(0_0_0/0.2)]">
            <p className="border-b border-line px-3 py-2 font-mono text-[10px] tracking-[0.12em] text-fg-muted uppercase">Live preview</p>
            <div className="max-h-[calc(100vh-7rem)] overflow-y-auto p-3">{previewContents}</div>
          </div>
        </aside>
      </div>

      <div className="fixed inset-x-0 bottom-16 z-20 mx-auto w-full max-w-2xl px-4 sm:px-6 lg:hidden">
        <div className="overflow-hidden rounded-t-card border border-b-0 border-line bg-surface-raised shadow-[0_-8px_24px_rgb(0_0_0/0.4)]">
          <button type="button" onClick={() => setDockOpen((v) => !v)} className="flex w-full items-center justify-between px-3 py-2">
            <span className="font-mono text-[10px] tracking-[0.12em] text-fg-muted uppercase">Live preview</span>
            {dockOpen ? <ChevronDown className="h-4 w-4" /> : <ChevronUp className="h-4 w-4" />}
          </button>
          {dockOpen ? (
            <div className="max-h-[46vh] overflow-y-auto border-t border-line p-3">{previewContents}</div>
          ) : null}
        </div>
      </div>
    </div>
  );
}

function FieldBlock({ label, children }: { label: string; children: ReactNode }) {
  return (
    <div>
      <p className="mb-1.5 font-mono text-[9px] tracking-[0.1em] text-fg-muted uppercase">{label}</p>
      {children}
    </div>
  );
}

function PlayerCandidatePicker({
  allOptions,
  matchingOptions,
  position,
  search,
  selectedIds,
  onPositionChange,
  onSearchChange,
  onToggle,
}: {
  allOptions: Option[];
  matchingOptions: Option[];
  position: string;
  search: string;
  selectedIds: string[];
  onPositionChange: (position: string) => void;
  onSearchChange: (search: string) => void;
  onToggle: (id: string) => void;
}) {
  const selected = allOptions.filter((option) => selectedIds.includes(option.id));
  const narrowed = position !== "all" || search.trim().length > 0;
  const results = narrowed ? matchingOptions.slice(0, 25) : [];
  return (
    <>
      <FieldBlock label={`Selected candidates — ${selected.length}`}>
        {selected.length ? (
          <div className="flex flex-wrap gap-1.5">
            {selected.map((option) => (
              <button key={option.id} type="button" onClick={() => onToggle(option.id)} className="flex items-center gap-1.5 rounded border border-panel-fg bg-panel-fg px-2 py-1.5 text-left text-panel">
                <OptionIcon option={option} className="h-5 w-5" />
                <span className="font-mono text-[10px] uppercase">{option.label}</span>
                <span aria-hidden className="font-mono text-xs">×</span>
              </button>
            ))}
          </div>
        ) : <p className="text-sm text-fg-muted">Search or filter to add candidates.</p>}
      </FieldBlock>
      <FieldBlock label="Find players">
      <div className="flex flex-col gap-2">
        <div className="flex flex-wrap gap-1.5">
          {["all", "QB", "RB", "WR", "TE", "other"].map((value) => (
            <button
              key={value}
              type="button"
              onClick={() => onPositionChange(value)}
              className={`px-3 py-2 font-slab text-xs uppercase ${position === value ? "bg-panel text-panel-fg" : "bg-surface-raised text-fg-muted ring-1 ring-line ring-inset"}`}
            >
              {value === "all" ? "All positions" : value === "other" ? "Other positions" : value}
            </button>
          ))}
        </div>
        <input
          type="search"
          value={search}
          onChange={(event) => onSearchChange(event.target.value)}
          placeholder="Search player or team"
          className="w-full rounded border border-line bg-surface-raised px-3 py-2 text-sm"
        />
      </div>
      </FieldBlock>
      <FieldBlock label={narrowed ? `Matching players — ${matchingOptions.length} found` : "Matching players"}>
        {!narrowed ? <p className="text-sm text-fg-muted">Choose a position or search by player or team to browse.</p> : (
          <>
            <div className="max-h-80 overflow-y-auto rounded border border-line">
              {results.map((option) => {
                const selected_ = selectedIds.includes(option.id);
                return (
                  <button key={option.id} type="button" onClick={() => onToggle(option.id)} className={`flex w-full items-center gap-2 border-b border-line px-3 py-2 text-left last:border-b-0 ${selected_ ? "bg-panel-shade" : "hover:bg-panel-shade"}`}>
                    <OptionIcon option={option} className="h-6 w-6" />
                    <span className="min-w-0 flex-1 truncate font-slab text-sm uppercase">{option.label}</span>
                    <span className="font-mono text-[10px] text-fg-muted uppercase">{option.sublabel}</span>
                    <span className="font-mono text-[10px] uppercase">{selected_ ? "Remove" : "Add"}</span>
                  </button>
                );
              })}
              {!results.length ? <p className="px-3 py-3 text-sm text-fg-muted">No active players match those filters.</p> : null}
            </div>
            {matchingOptions.length > results.length ? <p className="mt-1 text-xs text-fg-muted">Showing the first {results.length}; refine the search to narrow further.</p> : null}
          </>
        )}
      </FieldBlock>
    </>
  );
}
