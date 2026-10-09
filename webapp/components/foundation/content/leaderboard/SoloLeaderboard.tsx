import { BoardList, FindFriendsLink, ScopeNav, StandingBlock, type BoardRow } from "@/components/foundation/content/leaderboard/LeaderboardParts";
import { ModeToggle } from "@/components/foundation/content/leaderboard/ModeToggle";
import {
  boardHref,
  formatSoloScore,
  soloStandingCopy,
  type LeaderboardBoard,
  type QbMode,
  type SoloStanding,
} from "@/lib/foundation/content/leaderboard/boards";
import type { LeaderboardScope } from "@/lib/foundation/content/leaderboard/windows";

export type SoloRow = {
  rank: number;
  profileId: string;
  displayName: string;
  avatarUrl: string | null;
  username?: string | null;
  bestScore: number;
  isMe: boolean;
};

const BOARD_COPY: Record<"higher-or-lower" | "qb-season-builder", { caption: string; valueLabel: string; rule: string }> = {
  "higher-or-lower": {
    caption: "Best solo streak, all time",
    valueLabel: "Streak",
    rule: "Ranked on your longest solo streak. Multiplayer games don't count.",
  },
  "qb-season-builder": {
    caption: "Best season score, all time",
    valueLabel: "Score",
    rule: "Ranked on your best single season. Visible and Hidden runs have their own boards.",
  },
};

/** An all-time best-run board for one solo game. QB Season Builder adds a Visible / Hidden toggle. */
export function SoloLeaderboard({
  board,
  mode,
  scope = "all",
  rows,
  standing,
}: {
  board: Extract<LeaderboardBoard, "higher-or-lower" | "qb-season-builder">;
  mode?: QbMode;
  scope?: LeaderboardScope;
  rows: SoloRow[];
  standing: SoloStanding;
}) {
  const copy = soloStandingCopy(standing, scope);
  const text = BOARD_COPY[board];
  const boardRows: BoardRow[] = rows.map((row) => ({
    rank: row.rank,
    profileId: row.profileId,
    displayName: row.displayName,
    avatarUrl: row.avatarUrl,
    username: row.username,
    isMe: row.isMe,
    value: formatSoloScore(row.bestScore, board),
  }));

  return (
    <div>
      <ScopeNav scope={scope} hrefFor={(key) => boardHref({ board, scope: key, mode })} />
      {board === "qb-season-builder" && mode ? (
        <ModeToggle mode={mode} hrefFor={(key) => boardHref({ board, scope, mode: key })} />
      ) : null}

      <div className="mt-4">
        <StandingBlock
          ranked={standing.status === "ranked"}
          rank={standing.rank}
          detailLine={copy.detail}
          headline={copy.headline}
          detail={copy.detail}
          value={standing.bestScore === null ? null : formatSoloScore(standing.bestScore, board)}
        />
      </div>

      <div className="mt-6 flex flex-wrap items-baseline justify-between gap-2 type-label text-fg-muted">
        <span>{text.caption}</span>
        <span>
          {standing.rankedCount.toLocaleString("en-US")} ranked {scope === "friends" ? "on your friends board" : "players"}
        </span>
      </div>

      <BoardList
        rows={boardRows}
        valueLabel={text.valueLabel}
        empty={
          scope === "friends"
            ? {
                title: "No friends on the board yet",
                body: (
                  <>
                    Add friends to see how you stack up against them. <FindFriendsLink />
                  </>
                ),
              }
            : { title: "No one is ranked yet", body: "Finish a solo run to put the first score on this board." }
        }
      />

      <p className="mt-5 text-sm leading-6 text-fg-muted">{text.rule}</p>
    </div>
  );
}
