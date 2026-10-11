import { ArrowUpRight } from "lucide-react";
import Link from "next/link";

import { AuthorAvatar } from "@/components/foundation/content/prompts/AuthorIdentity";
import { Badge } from "@/components/foundation/ui-kit/Badge";
import { ButtonLink } from "@/components/foundation/ui-kit/Button";
import { formatSoloScore, soloBoardHref, type SoloBoard } from "@/lib/foundation/content/leaderboard/boards";
import { timeAgo, type ActivityItem } from "@/lib/foundation/friends/friends";
import { MATCH_GAME_NAMES } from "@/lib/platform/orchestration/catalog";

/** The card's out-link label: underlined, with an arrow to say it leaves the feed. */
function OutLabel({ children }: { children: string }) {
  return (
    <>
      <span className="underline underline-offset-2">{children}</span>
      <ArrowUpRight aria-hidden className="h-3.5 w-3.5 shrink-0" strokeWidth={1.8} />
    </>
  );
}

const LINK = "focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-fg";

function gameName(game: string | null) {
  return game && game in MATCH_GAME_NAMES ? MATCH_GAME_NAMES[game as keyof typeof MATCH_GAME_NAMES] : "a game";
}

/** "you", "you and Ava", "Ava, Ben and 2 others": who a win was over. Only the caller and their friends are named. */
export function beatLine(opponents: string[], you: boolean, count: number): string | null {
  const names = [...(you ? ["you"] : []), ...opponents];
  if (count === 0) return null;
  const others = count - names.length;
  if (names.length === 0) return `${count} ${count === 1 ? "player" : "players"}`;
  const shown = others > 0 ? [...names, `${others} ${others === 1 ? "other" : "others"}`] : names;
  return shown.length === 1 ? shown[0] : `${shown.slice(0, -1).join(", ")} and ${shown[shown.length - 1]}`;
}

/**
 * A multiplayer win or a new solo best: a short card beside the take cards,
 * with the same author line but a lighter body so the answers stay the main
 * thing. A high score leads with the number and where it puts the friend among
 * the viewer's circle; a win names who it was over. Wins by one friend on the
 * same day arrive folded into one card.
 */
export function GameMomentCard({ item }: { item: ActivityItem }) {
  const { event } = item;
  return (
    <article className="rounded-card border border-line bg-surface-raised">
      <div className="flex items-center gap-2.5 px-4 pt-3">
        <AuthorAvatar name={event.displayName} avatarUrl={event.avatarUrl} className="h-7 w-7" />
        <div className="min-w-0 leading-none">
          {event.username ? (
            <Link href={`/u/${event.username}`} className={`block truncate font-mono text-[15px] font-bold hover:text-fg-muted ${LINK}`}>
              {event.displayName}
            </Link>
          ) : (
            <p className="truncate font-mono text-[15px] font-bold">{event.displayName}</p>
          )}
          {event.username ? <p className="mt-1 truncate type-label text-fg-muted">@{event.username}</p> : null}
        </div>
        <span className="ml-auto shrink-0 font-mono text-[10px] tracking-[0.04em] text-fg-muted">{timeAgo(event.occurredAt).toUpperCase()}</span>
      </div>
      {event.type === "high_score" ? <HighScore item={item} /> : <Win item={item} />}
    </article>
  );
}

function HighScore({ item }: { item: ActivityItem }) {
  const { event } = item;
  const board: SoloBoard | null =
    event.game === "higher_or_lower" ? "higher-or-lower" : event.game === "qb_season_builder" ? "qb-season-builder" : null;
  const qb = board === "qb-season-builder";
  const hidden = qb && event.mode === "hidden";
  const score = board && event.rawScore !== null ? formatSoloScore(event.rawScore, board) : null;
  return (
    <div className="flex items-end gap-4 px-4 pt-3 pb-4">
      <div className="min-w-0 flex-1">
        <div className="flex items-center gap-2">
          <Badge size="xs">New best</Badge>
          <span className="truncate type-label text-fg-muted">
            in{" "}
            {board ? (
              <Link href={soloBoardHref({ board, scope: "friends", mode: hidden ? "hidden" : undefined })} className={`underline underline-offset-2 hover:text-fg ${LINK}`}>
                {gameName(event.game)}
              </Link>
            ) : (
              gameName(event.game)
            )}
            {qb && event.mode ? ` · ${event.mode}` : ""}
          </span>
        </div>
        <p className="mt-2 flex items-baseline gap-2">
          <span className="font-slab text-[44px] leading-none">{score ?? "—"}</span>
          <span className="type-label text-fg-muted">{qb ? "season score" : "in a row"}</span>
        </p>
        {event.friendRank !== null && event.friendCount !== null && event.friendCount > 1 ? (
          <p className="mt-1.5 text-[15px] leading-6 text-fg-muted">
            #{event.friendRank} of {event.friendCount} among you and your friends
          </p>
        ) : null}
      </div>
      <ButtonLink href="/solo" variant="ghost" size="sm" fullWidth={false}>
        <OutLabel>Beat it</OutLabel>
      </ButtonLink>
    </div>
  );
}

function Win({ item }: { item: ActivityItem }) {
  const { event, more } = item;
  const wins = [event, ...more];
  const games = [...new Set(wins.map((win) => gameName(win.game)))];
  const beat = wins.length === 1 ? beatLine(event.opponents, event.opponentYou, event.opponentCount) : null;
  return (
    <div className="flex items-end gap-4 px-4 pt-3 pb-4">
      <div className="min-w-0 flex-1">
        <Badge size="xs">{wins.length === 1 ? "Win" : `${wins.length} wins`}</Badge>
        <p className="mt-2 text-lg leading-7 font-medium">
          {wins.length === 1 ? `Won ${games[0]}` : games.length === 1 ? `Won ${wins.length} ${games[0]} games` : `Won ${wins.length} games: ${games.join(", ")}`}
        </p>
        {beat || (wins.length === 1 && event.rawScore !== null) ? (
          <p className="mt-0.5 text-[15px] leading-6 text-fg-muted">
            {beat ? `Beat ${beat}` : ""}
            {beat && wins.length === 1 && event.rawScore !== null ? " · " : ""}
            {wins.length === 1 && event.rawScore !== null ? `Score ${event.rawScore}` : ""}
          </p>
        ) : null}
      </div>
      <ButtonLink href="/party" variant="ghost" size="sm" fullWidth={false}>
        <OutLabel>Play</OutLabel>
      </ButtonLink>
    </div>
  );
}
