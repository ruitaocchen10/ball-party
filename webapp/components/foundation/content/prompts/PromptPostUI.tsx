"use client";

import { Check, ChevronDown, ChevronLeft, ChevronRight, ChevronUp, Lock } from "lucide-react";
import Link from "next/link";
import { useState, type ReactNode } from "react";

import { Button } from "@/components/foundation/ui-kit/Button";
import { Card } from "@/components/foundation/ui-kit/Card";
import { Input, Textarea } from "@/components/foundation/ui-kit/Input";
import { Select } from "@/components/foundation/ui-kit/Select";
import type { NflScheduleGame } from "@/lib/foundation/content/nfl/schedule";
import { OptionIcon } from "./SlotFaces";
import { MatchupPicker } from "./MatchupPicker";
import { PickOneBoard } from "./PickOneBoard";
import { COVER_LOGO_COUNT, CoverShape, PromptCover } from "./PromptCover";
import { SharePromptButton } from "./SharePromptButton";
import { usePromptDeadlineNow } from "./usePromptDeadline";
import {
  CheckboxPoolField,
  GameSelectField,
  OPINION_ONLY_KINDS,
  TEMPLATE_DEFS,
  boldLockBounds,
  defaultBoldLockAt,
  buildGamePickSlots,
  buildWeeklyPickSlots,
  buildPowerRankingSlots,
  buildRankingSlots,
  buildStatLeaderSlots,
  buildWeeklyAwardsSlots,
  type ComposerKind,
  defaultCriteria,
  defaultPromptText,
  optionPoolFor,
} from "./ComposerFields";
import { COVER_OPTION_LIMIT, coverOptions, isPicksPost, isPromptOpenForAnswers, needsCoverChoice, relativeTime } from "@/lib/foundation/content/prompts/logic";
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
  const now = usePromptDeadlineNow(post);
  const promptOpen = isPromptOpenForAnswers(post, now);
  const canAnswer = promptOpen && !post.viewerAnswered;
  const void_ = post.status === "void";
  const bold = post.templateKind === "bold_predictions";
  const actionLabel = bold
    ? promptOpen ? "Make your predictions" : "See predictions"
    : canAnswer ? "Make your picks" : post.viewerAnswered && promptOpen ? "View your picks" : "See takes";
  const timingLabel = postTimingLabel(post, now);
  const statusChip = post.viewerAnswered
    ? <span className="inline-flex shrink-0 items-center gap-1 bg-grade-elite px-2 py-1 type-label-xs font-bold leading-none text-[#fffdf7]"><Check aria-hidden className="h-3 w-3" strokeWidth={3} /> Complete</span>
    : post.status !== "void" && !promptOpen && post.status !== "resolved"
      ? <span className="inline-flex shrink-0 items-center gap-1 border border-fg-muted/50 bg-surface px-2 py-1 type-label-xs font-bold leading-none text-fg-muted"><Lock aria-hidden className="h-3 w-3" strokeWidth={2.5} /> Locked</span>
      : post.status === "resolved"
        ? <span className="inline-flex shrink-0 border border-panel/50 bg-panel/10 px-2 py-1 type-label-xs font-bold leading-none text-panel">Resolved</span>
      : null;

  return (
    <Card edge={false} className={`rounded-none border border-line !bg-surface-raised !text-fg !shadow-[0_10px_24px_rgb(0_0_0/0.4)] ${void_ ? "opacity-45" : ""}`}>
      <div className="flex items-start gap-3 px-4 pt-4">
        <h2 className="min-w-0 flex-1 font-slab text-2xl leading-[1.05] uppercase">{post.promptText}</h2>
        {statusChip ?? <span className="shrink-0 pt-0.5 type-label text-fg-muted">{timingLabel}</span>}
      </div>
      <p className="px-4 pt-1 text-[13px] text-fg-muted">{post.caption}</p>

      {void_ ? (
        <p className="mx-4 mt-3 flex items-center gap-2 bg-surface px-3 py-2 type-label text-fg-muted">
          {post.voidReason}
        </p>
      ) : null}

      <PostTeaser post={post} gameContexts={gameContexts} />
      <div className="flex items-center justify-between gap-3 px-4 pt-4">
        <p className="type-label text-fg-muted">
          {bold
            ? `${post.predictionCount ?? 0} ${post.predictionCount === 1 ? "prediction" : "predictions"} made`
            : `${post.responseCount} ${post.responseCount === 1 ? "person has" : "people have"} answered`}
        </p>
      </div>
      <div className="px-4 pt-3 pb-4">
        {(bold ? promptOpen : canAnswer) && !viewerCanAnswer ? (
          <Link href="/login?next=/" className="flex h-12 items-center justify-center bg-panel px-4 font-slab text-[15px] tracking-[0.04em] text-panel-fg uppercase hover:bg-panel-hover">
            Sign up to answer
          </Link>
        ) : (
          <Button variant="solid" fullWidth onClick={onOpenAnswer}>{actionLabel}</Button>
        )}
      </div>
    </Card>
  );
}

function postTimingLabel(post: Post, now: number) {
  return isPromptOpenForAnswers(post, now) ? `Closes ${relativeTime(post.lockAt)}` : relativeTime(post.createdAt);
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

  if (post.templateKind === "power_rankings") {
    return <PowerRankingsBoard post={post} />;
  }

  if (post.templateKind === "bold_predictions") {
    return <BoldPredictionsCover />;
  }

  if (post.templateKind === "weekly_awards") {
    return <WeeklyAwardsCover />;
  }

  if (post.templateKind === "stat_leader" && post.slots.length === 1) {
    const pool = post.slots[0].options;
    return <PickOneBoard options={coverOptions(pool)} poolSize={pool.length} />;
  }

  const allOptions = post.slots.flatMap((slot) => slot.options);
  const options = [...new Map(allOptions.map((option) => [option.id, option])).values()];
  const shown = options.slice(0, 6);
  const overflow = options.length - shown.length;

  return (
    <div className="mt-3 flex flex-col items-center gap-2 px-4">
      {post.slots.length > 1 ? (
        <p className="type-label text-fg-muted">{post.slots.length} picks to make</p>
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

const COVER_TEAM_COUNT = COVER_LOGO_COUNT;

function BoldPredictionsCover() {
  return (
    <PromptCover
      testId="bold-predictions-cover"
      ariaLabel="Bold Predictions"
      title={["Bold", "Predictions"]}
      subtitle="Call it before it happens"
      leftGlow="bg-[radial-gradient(ellipse_at_left,rgb(245_158_11_/_0.24),transparent_70%)]"
      rightGlow="bg-[radial-gradient(ellipse_at_right,rgb(239_68_68_/_0.22),transparent_70%)]"
      art={
        <>
          <CoverShape shape="bolt" className="top-2 left-4 h-28 w-24 rotate-[-12deg] text-amber-400/75 sm:h-32 sm:w-28" />
          <CoverShape shape="bolt" className="top-24 left-24 h-16 w-14 rotate-[10deg] text-amber-400/45" />
          <CoverShape shape="bolt" className="bottom-3 left-3 h-14 w-12 rotate-[-6deg] text-amber-400/30" />
          <CoverShape shape="bolt" className="right-4 bottom-2 h-28 w-24 rotate-[168deg] text-red-500/75 sm:h-32 sm:w-28" />
          <CoverShape shape="bolt" className="top-6 right-24 h-16 w-14 rotate-[190deg] text-red-500/45" />
          <CoverShape shape="bolt" className="top-3 right-3 h-14 w-12 rotate-[174deg] text-red-500/30" />
        </>
      }
    />
  );
}

function WeeklyAwardsCover() {
  return (
    <PromptCover
      testId="weekly-awards-cover"
      ariaLabel="Weekly Awards"
      title={["Weekly", "Awards"]}
      subtitle="Hand out the hardware"
      leftGlow="bg-[radial-gradient(ellipse_at_left,rgb(250_204_21_/_0.24),transparent_70%)]"
      rightGlow="bg-[radial-gradient(ellipse_at_right,rgb(239_68_68_/_0.22),transparent_70%)]"
      art={
        <>
          <CoverShape shape="star" className="top-2 left-4 h-28 w-28 rotate-[-12deg] text-yellow-400/75 sm:h-32 sm:w-32" />
          <CoverShape shape="star" className="top-24 left-24 h-16 w-16 rotate-[10deg] text-yellow-400/45" />
          <CoverShape shape="star" className="bottom-3 left-3 h-14 w-14 rotate-[-6deg] text-yellow-400/30" />
          <CoverShape shape="star" className="right-4 bottom-2 h-28 w-28 rotate-[12deg] text-red-500/75 sm:h-32 sm:w-32" />
          <CoverShape shape="star" className="top-6 right-24 h-16 w-16 rotate-[-10deg] text-red-500/45" />
          <CoverShape shape="star" className="top-3 right-3 h-14 w-14 rotate-[6deg] text-red-500/30" />
        </>
      }
    />
  );
}

/**
 * The Power Rankings cover shows six teams the admin chose while composing
 * the prompt. It is the same for every viewer, in placement order.
 */
function PowerRankingsBoard({ post }: { post: Post }) {
  const byTeamCode = new Map(post.slots[0]?.options.filter((option) => option.teamCode).map((option) => [option.teamCode!, option]) ?? []);
  const options = (post.coverTeamCodes ?? []).map((teamCode) => byTeamCode.get(teamCode)).filter((option): option is Option => Boolean(option));

  return (
    <PromptCover
      testId="power-rankings-board"
      ariaLabel="Power Rankings board"
      title={["Power", "Rankings"]}
      subtitle="Your NFL standings"
      leftGlow="bg-[radial-gradient(ellipse_at_left,rgb(34_197_94_/_0.18),transparent_68%)]"
      rightGlow="bg-[radial-gradient(ellipse_at_right,rgb(239_68_68_/_0.18),transparent_68%)]"
      logos={options}
      art={
        <>
          <CoverShape shape="chevronUp" className="top-1 left-3 h-12 w-20 text-green-400/70" />
          <CoverShape shape="chevronUp" className="top-11 left-10 h-10 w-16 text-green-400/45" />
          <CoverShape shape="chevronUp" className="top-20 left-2 h-8 w-12 text-green-400/25" />
          <CoverShape shape="chevronDown" className="right-3 bottom-1 h-12 w-20 text-red-500/70" />
          <CoverShape shape="chevronDown" className="right-10 bottom-11 h-10 w-16 text-red-500/45" />
          <CoverShape shape="chevronDown" className="right-2 bottom-20 h-8 w-12 text-red-500/25" />
        </>
      }
    />
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

/** What "the setup is ready" means for each template, in the publish checklist. */
const SETUP_CHECK_LABELS: Record<ComposerKind, string> = {
  game_pick: "At least one game selected",
  weekly_picks: "At least one game selected",
  weekly_awards: "A week with scheduled games selected",
  bold_predictions: "A week with scheduled games selected",
  stat_leader: "Candidates chosen (and prompt art, for a big pool)",
  ranking: "Candidates chosen to rank",
  power_rankings: `${COVER_TEAM_COUNT} cover teams chosen`,
};

/** Heading for the template-specific section, since what it holds differs per template. */
const SETUP_SECTION_TITLES: Record<ComposerKind, string> = {
  game_pick: "Game",
  weekly_picks: "Game",
  weekly_awards: "Week",
  bold_predictions: "Week",
  stat_leader: "Candidates",
  ranking: "What to rank",
  power_rankings: "Cover art",
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
  const [kind, setKind] = useState<ComposerKind>("game_pick");
  const [isOpinion, setIsOpinion] = useState(false);
  const [gameId, setGameId] = useState(initialGame?.id ?? "");
  const [season, setSeason] = useState(String(initialGame?.season ?? ""));
  const [week, setWeek] = useState(String(initialGame?.week ?? ""));
  const [weeklyGameIds, setWeeklyGameIds] = useState<string[]>([]);
  const [playerIds, setPlayerIds] = useState<string[]>([]);
  // Players shown in a pick-one prompt's art, in placement order — only used once the pool outgrows the art.
  const [coverPlayerIds, setCoverPlayerIds] = useState<string[]>([]);
  const [playerPosition, setPlayerPosition] = useState("all");
  const [playerSearch, setPlayerSearch] = useState("");
  const [rankingTarget, setRankingTarget] = useState<"teams" | "players" | "games">("teams");
  const [rankingIds, setRankingIds] = useState<string[]>([]);
  const [rankCount, setRankCount] = useState(1);
  // Team codes in placement order; the Power Rankings cover shows exactly six.
  const [coverTeamCodes, setCoverTeamCodes] = useState<string[]>([]);
  // Defaults live with each template's slot builder. This map only remembers
  // an author's deliberate overrides, including one value per game in a set.
  const [pointsBySlot, setPointsBySlot] = useState<Record<string, number>>({});
  const [caption, setCaption] = useState("");
  const [promptText, setPromptText] = useState(defaultPromptText("game_pick", initialGame));
  const [criteria, setCriteria] = useState(defaultCriteria("game_pick"));
  const [lockAt, setLockAt] = useState(defaultLockAt);

  function pickTemplate(next: ComposerKind) {
    setKind(next);
    if (next === "game_pick" || next === "weekly_picks" || next === "weekly_awards" || next === "bold_predictions") {
      setPromptText(defaultPromptText(next, selectedGame ?? weeklyGames[0]));
      if (next === "bold_predictions") setBoldLockFor(season, week);
      if (next === "weekly_picks") setWeeklyGameIds((current) => current.length ? current : weeklyGames.map((game) => game.id));
    } else {
      setPromptText(defaultPromptText(next, games.find((game) => game.id === gameId)));
    }
    // Power Rankings and Weekly Awards are personal opinions, never a question
    // with a single correct answer to grade.
    const nextOpinion = OPINION_ONLY_KINDS.includes(next) ? true : OPINION_ONLY_KINDS.includes(kind) ? false : isOpinion;
    setIsOpinion(nextOpinion);
    setCriteria(nextOpinion && next !== "weekly_awards" && next !== "bold_predictions" ? OPINION_CRITERIA : defaultCriteria(next));
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

  /** A Bold Predictions post locks shortly before its week's first kickoff, so choosing the week proposes that time. */
  function setBoldLockFor(forSeason: string, forWeek: string) {
    const suggested = defaultBoldLockAt(games, Number(forSeason), Number(forWeek));
    if (suggested) setLockAt(toLocalInputValue(suggested));
  }

  function selectSchedulePeriod(nextSeason: string, nextWeek: string, template = kind) {
    const nextGames = games.filter((game) => String(game.season) === nextSeason && String(game.week) === nextWeek);
    setSeason(nextSeason);
    setWeek(nextWeek);
    setGameId(nextGames[0]?.id ?? "");
    setWeeklyGameIds(nextGames.map((game) => game.id));
    setPromptText(defaultPromptText(template, nextGames[0]));
    if (template === "bold_predictions") setBoldLockFor(nextSeason, nextWeek);
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

  // A candidate dropped from the pool can't stay in the art.
  const coverIds = coverPlayerIds.filter((id) => playerIds.includes(id));

  const defaultSlots =
    kind === "game_pick"
      ? selectedGame ? buildGamePickSlots(selectedGame) : []
      : kind === "weekly_picks"
      ? weeklyGames.filter((game) => weeklyGameIds.includes(game.id)).flatMap(buildWeeklyPickSlots)
      : kind === "weekly_awards"
      ? buildWeeklyAwardsSlots(weeklyGames)
      : kind === "stat_leader"
        ? buildStatLeaderSlots(players.filter((p) => playerIds.includes(p.id)), coverIds)
        : kind === "power_rankings"
          ? buildPowerRankingSlots()
          : kind === "ranking"
          ? effectiveRankCount > 0
            ? buildRankingSlots(rankingOptions.filter((option) => rankingIds.includes(option.id)), effectiveRankCount)
            : []
          : [];
  const slots = defaultSlots.map((slot) => ({
    ...slot,
    points: pointsBySlot[slot.id] ?? slot.points,
  }));
  const hasInvalidPoints = slots.some((slot) => !Number.isInteger(slot.points) || slot.points < 1 || slot.points > 32767);

  const templateName = TEMPLATE_DEFS.find((t) => t.kind === kind)!.name;
  const lockAtDate = new Date(lockAt);
  const lockInPast = isInPast(lockAt);
  // The reveal is tied to the week the lock time falls before (0171), so the lock
  // must sit between the previous week's last kickoff and this week's first.
  const boldBounds = boldLockBounds(games, Number(season), Number(week));
  const boldLockOk = Boolean(boldBounds.firstKickoff)
    && lockAtDate.getTime() <= boldBounds.firstKickoff!.getTime()
    && (!boldBounds.previousEnd || lockAtDate.getTime() > boldBounds.previousEnd.getTime());

  // The same conditions that used to sit inline on Publish's `disabled`, split
  // out so the checklist beside the button can say which one is holding it back.
  // A Bold Predictions post has no slots — its answers are free text — so it is
  // ready once there is a week to be about.
  const setupReady =
    (slots.length > 0 || kind === "bold_predictions")
    && !((kind === "weekly_awards" || kind === "bold_predictions") && weeklyGames.length === 0)
    && !(kind === "ranking" && effectiveRankCount === 0)
    && !(kind === "power_rankings" && coverTeamCodes.length !== COVER_TEAM_COUNT)
    && !(kind === "stat_leader" && needsCoverChoice(slots[0]?.options ?? []));
  const checklist = [
    { label: SETUP_CHECK_LABELS[kind], ok: setupReady },
    { label: "Every point value is a whole number, 1 or more", ok: !hasInvalidPoints },
    { label: "Lock time is in the future", ok: !lockInPast },
    ...(kind === "bold_predictions" ? [{ label: `Locks after Week ${Number(week) - 1} ends and before Week ${week} kicks off`, ok: boldLockOk }] : []),
  ];
  const canPublish = !pending && checklist.every((item) => item.ok);
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
    coverTeamCodes: kind === "power_rankings" ? coverTeamCodes : undefined,
    slots,
    comments: [],
  };

  const previewContents = (
    <>
      <PostCardC post={previewPost} viewerCanAnswer onOpenAnswer={() => {}} />
      <div className="mt-3">
        {error ? <p role="alert" className="mb-2 type-label text-grade-rough">{error}</p> : null}
        <ul className="mb-3 flex flex-col gap-1.5 border border-line px-3 py-2.5">
          {checklist.map((item) => (
            <li key={item.label} className={`flex items-center gap-2 text-sm ${item.ok ? "text-fg" : "text-fg-muted"}`}>
              <span aria-hidden className="w-3 text-center font-mono text-xs">{item.ok ? "✓" : "○"}</span>
              <span>{item.label}</span>
            </li>
          ))}
        </ul>
        <Button
          fullWidth
          disabled={!canPublish}
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
              ...(kind === "power_rankings" ? { coverTeamCodes } : {}),
              ...((kind === "game_pick" || kind === "weekly_picks") && !isOpinion ? { resolutionSource: { provider: "nflverse", rule: "winner" } } : {}),
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
        {kind === "stat_leader" ? <div className="mt-2"><SharePromptButton promptText={promptText} options={slots[0]?.options ?? []} /></div> : null}
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
        {kind === "stat_leader" ? <div className="w-full max-w-xs"><SharePromptButton promptText={promptText} options={slots[0]?.options ?? []} /></div> : null}
        <div className="flex gap-2">
          <Button
            variant="ghost"
            onClick={() => {
              setPublished(false);
              setKind("game_pick");
              setCaption("");
              setPlayerIds([]);
              setCoverPlayerIds([]);
              setRankingIds([]);
              setRankCount(1);
              setCoverTeamCodes([]);
              setGameId(initialGame?.id ?? "");
              setWeeklyGameIds([]);
              setPromptText(defaultPromptText("game_pick", initialGame));
              setCriteria(defaultCriteria("game_pick"));
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
            className="flex h-12 items-center bg-panel px-4 font-slab text-[15px] tracking-[0.04em] text-panel-fg uppercase hover:bg-panel-hover"
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
          <div className="flex flex-col gap-4">
        <Section n={1} title="Template">
        <div>
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
          <p className="mt-2 text-sm text-fg-muted">{TEMPLATE_DEFS.find((t) => t.kind === kind)?.blurb}</p>
        </div>

        {!OPINION_ONLY_KINDS.includes(kind) ? (
          <button
            type="button"
            role="checkbox"
            aria-checked={isOpinion}
            onClick={toggleOpinion}
            className={`flex w-full items-start gap-3 border px-3.5 py-3 text-left ${isOpinion ? "border-fg" : "border-line"}`}
          >
            <span aria-hidden className={`mt-0.5 flex h-[18px] w-[18px] shrink-0 items-center justify-center border ${isOpinion ? "border-fg bg-fg text-surface" : "border-fg-muted"}`}>
              {isOpinion ? <Check className="h-3 w-3" strokeWidth={3} /> : null}
            </span>
            <span>
              <span className="block font-semibold">Opinion prompt</span>
              <span className="text-sm text-fg-muted">No correct answer, no points</span>
            </span>
          </button>
        ) : null}
        </Section>

        <Section n={2} title={SETUP_SECTION_TITLES[kind]}>

        {kind === "game_pick" || kind === "weekly_picks" || kind === "weekly_awards" || kind === "bold_predictions" ? (
          <>
            <div className="flex flex-wrap items-start gap-4">
              <FieldBlock label="Season">
                <Select name="picks-season" ariaLabel="NFL season" value={season} onValueChange={(nextSeason) => selectSchedulePeriod(nextSeason, firstWeekForSeason(nextSeason))} options={seasons.map((value) => ({ value: String(value), label: String(value) }))} />
              </FieldBlock>
              <FieldBlock label="Week">
                <Select name="picks-week" ariaLabel="NFL week" value={week} onValueChange={(nextWeek) => selectSchedulePeriod(season, nextWeek)} options={weeks.map((value) => ({ value: String(value), label: `Week ${value}` }))} />
              </FieldBlock>
              {kind === "game_pick" ? <FieldBlock label="Game">
                {weeklyGames.length ? <GameSelectField value={gameId} onChange={(id) => {
                  setGameId(id);
                  setPromptText(defaultPromptText("game_pick", weeklyGames.find((game) => game.id === id)));
                }} games={weeklyGames} /> : <p className="text-sm text-fg-muted">The NFL schedule is temporarily unavailable. Try again shortly.</p>}
              </FieldBlock> : null}
            </div>
            {kind === "weekly_picks" ? <FieldBlock label="Games — all selected by default">
              {weeklyGames.length ? <CheckboxPoolField options={weeklyGames.map((game) => ({ id: game.id, label: game.label, sublabel: new Date(game.kickoff).toLocaleString(), teamCodes: [game.away, game.home] }))} selectedIds={weeklyGameIds} onToggle={(id) => setWeeklyGameIds((current) => current.includes(id) ? current.filter((gameId_) => gameId_ !== id) : [...current, id])} roomyTeams /> : <p className="text-sm text-fg-muted">Choose a season and week with scheduled games.</p>}
            </FieldBlock> : null}
          </>
        ) : null}
        {kind === "stat_leader" ? (
          <>
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
            {playerIds.length > COVER_OPTION_LIMIT ? (
              <FieldBlock label={`Prompt art players — choose ${COVER_OPTION_LIMIT} of ${playerIds.length} (${coverIds.length}/${COVER_OPTION_LIMIT})`}>
                <CheckboxPoolField
                  options={allPlayerOptions.filter((option) => playerIds.includes(option.id))}
                  selectedIds={coverIds}
                  max={COVER_OPTION_LIMIT}
                  onToggle={(id) => setCoverPlayerIds((current) => current.includes(id) ? current.filter((value) => value !== id) : [...current, id])}
                />
                <p className="mt-2 text-xs text-fg-muted">Shown in the art in the order you pick them. Everyone can still answer with any of the {playerIds.length} candidates.</p>
              </FieldBlock>
            ) : null}
          </>
        ) : null}
        {kind === "power_rankings" ? (
          <>
            <FieldBlock label="Power Rankings setup">
              <p className="text-sm leading-6 text-fg-muted">Each person can choose Top 5, Top 10, or all 32 teams while answering. Their previous ranking will be used to show team movement.</p>
            </FieldBlock>
            <FieldBlock label={`Cover art teams — choose ${COVER_TEAM_COUNT} (${coverTeamCodes.length}/${COVER_TEAM_COUNT})`}>
              <CheckboxPoolField
                options={optionPoolFor("ranking")}
                selectedIds={coverTeamCodes}
                max={COVER_TEAM_COUNT}
                onToggle={(id) => setCoverTeamCodes((current) => current.includes(id) ? current.filter((code) => code !== id) : [...current, id])}
              />
              <p className="mt-2 text-xs text-fg-muted">Placed in the order you pick them: 1–2 are the large top logos, 3–4 the large bottom logos, 5–6 the smaller pair in the middle.</p>
            </FieldBlock>
          </>
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
              <div className="flex flex-wrap items-start gap-4">
                <FieldBlock label="Season">
                  <Select name="ranking-season" ariaLabel="Ranking NFL season" value={season} onValueChange={(nextSeason) => selectSchedulePeriod(nextSeason, firstWeekForSeason(nextSeason), "ranking")} options={seasons.map((value) => ({ value: String(value), label: String(value) }))} />
                </FieldBlock>
                <FieldBlock label="Week">
                  <Select name="ranking-week" ariaLabel="Ranking NFL week" value={week} onValueChange={(nextWeek) => selectSchedulePeriod(season, nextWeek, "ranking")} options={weeks.map((value) => ({ value: String(value), label: `Week ${value}` }))} />
                </FieldBlock>
              </div>
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
                className="w-24 border border-line bg-surface-raised px-3 py-2 text-sm disabled:opacity-40"
              />
              <p className="mt-1 text-xs text-fg-muted">People will order their top {effectiveRankCount || "N"} from the {rankingIds.length} candidates you selected.</p>
            </FieldBlock>
          </>
        ) : null}
        </Section>

        <Section n={3} title="Copy">
        <FieldBlock label="Prompt text">
          <Input variant="well" value={promptText} onChange={(e) => setPromptText(e.target.value)} />
        </FieldBlock>
        <FieldBlock label="Caption — optional">
          <Input variant="well" value={caption} onChange={(e) => setCaption(e.target.value)} />
        </FieldBlock>
        <FieldBlock label="Resolution criteria — shown before anyone answers">
          <Textarea variant="well" value={criteria} onChange={(e) => setCriteria(e.target.value)} rows={3} />
        </FieldBlock>
        </Section>

        <Section n={4} title="Scoring & timing">
        {!isOpinion && slots.length ? (
          <FieldBlock label="Points per slot">
            <div className="flex flex-col gap-2">
              {slots.map((slot) => (
                <label key={slot.id} className="flex items-center justify-between gap-4 border border-line bg-surface-raised px-3 py-2 text-sm">
                  <span>{slot.label}</span>
                  <span className="flex shrink-0 items-center gap-2 text-fg-muted">
                    <input
                      aria-label={`${slot.label} points`}
                      type="number"
                      min={1}
                      max={32767}
                      step={1}
                      value={slot.points}
                      onChange={(event) => {
                        const points = Number(event.target.value);
                        if (!Number.isInteger(points) || points < 0 || points > 32767) return;
                        setPointsBySlot((current) => ({ ...current, [slot.id]: points }));
                      }}
                      className="w-20 border border-line bg-surface px-2 py-1 text-right text-sm text-fg"
                    />
                    <span className="type-label">pts</span>
                  </span>
                </label>
              ))}
            </div>
          </FieldBlock>
        ) : null}

        <FieldBlock label="Locks at">
          <input
            type="datetime-local"
            value={lockAt}
            onChange={(e) => setLockAt(e.target.value)}
            className="w-full border border-line bg-surface-raised px-3 py-2 text-sm"
          />
          {lockInPast ? (
            <p className="mt-1 type-label-xs text-grade-rough">Pick a time in the future</p>
          ) : null}
        </FieldBlock>
        </Section>
          </div>
        </div>

        <aside className="sticky top-6 hidden lg:block">
          <div className="overflow-hidden rounded-card border border-line bg-surface-raised shadow-[0_8px_24px_rgb(0_0_0/0.2)]">
            <p className="border-b border-line px-3 py-2 type-label text-fg-muted">Live preview</p>
            <div className="max-h-[calc(100vh-7rem)] overflow-y-auto p-3">{previewContents}</div>
          </div>
        </aside>
      </div>

      <div className="fixed inset-x-0 bottom-16 z-20 mx-auto w-full max-w-2xl px-4 sm:px-6 lg:hidden">
        <div className="overflow-hidden rounded-t-card border border-b-0 border-line bg-surface-raised shadow-[0_-8px_24px_rgb(0_0_0/0.4)]">
          <button type="button" onClick={() => setDockOpen((v) => !v)} className="flex w-full items-center justify-between px-3 py-2">
            <span className="type-label text-fg-muted">Live preview</span>
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

/** A numbered card grouping one stage of the form, so the composer reads as four steps rather than one long column. */
function Section({ n, title, children }: { n: number; title: string; children: ReactNode }) {
  return (
    <section className="border border-line">
      <header className="flex items-center gap-3 border-b border-line px-4 py-3">
        <span aria-hidden className="flex h-[22px] w-[22px] items-center justify-center rounded-full border border-fg-muted font-mono text-[11px] text-fg-muted">{n}</span>
        <h2 className="font-slab text-lg leading-none uppercase">{title}</h2>
      </header>
      <div className="flex flex-col gap-4 p-4">{children}</div>
    </section>
  );
}

function FieldBlock({ label, children }: { label: string; children: ReactNode }) {
  return (
    <div>
      <p className="mb-1.5 type-label-xs text-fg-muted">{label}</p>
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
              <button key={option.id} type="button" onClick={() => onToggle(option.id)} className="flex items-center gap-1.5 border border-panel-fg bg-panel-fg px-2 py-1.5 text-left text-panel">
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
          className="w-full border border-line bg-surface-raised px-3 py-2 text-sm"
        />
      </div>
      </FieldBlock>
      <FieldBlock label={narrowed ? `Matching players — ${matchingOptions.length} found` : "Matching players"}>
        {!narrowed ? <p className="text-sm text-fg-muted">Choose a position or search by player or team to browse.</p> : (
          <>
            <div className="max-h-80 overflow-y-auto border border-line">
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
