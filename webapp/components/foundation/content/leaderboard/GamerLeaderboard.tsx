import { BoardList, FindFriendsLink, ScopeNav, StandingBlock, WindowNav, type BoardRow } from "@/components/foundation/content/leaderboard/LeaderboardParts";
import { boardHref, gamerStandingCopy, type GamerStanding } from "@/lib/foundation/content/leaderboard/boards";
import type { LeaderboardScope, LeaderboardWindow } from "@/lib/foundation/content/leaderboard/windows";

export type GamerRow = {
  rank: number;
  profileId: string;
  displayName: string;
  avatarUrl: string | null;
  username?: string | null;
  wins: number;
  gamesPlayed: number;
  isMe: boolean;
};

const WINDOW_CAPTION: Record<LeaderboardWindow, string> = {
  week: "Wins in the last 7 days",
  month: "Wins in the last 30 days",
  year: "Wins in the last 365 days",
  lifetime: "Every multiplayer win",
};

/** The multiplayer wins board: first-place finishes in rooms, ranked per window. */
export function GamerLeaderboard({
  window,
  scope = "all",
  rows,
  standing,
}: {
  window: LeaderboardWindow;
  scope?: LeaderboardScope;
  rows: GamerRow[];
  standing: GamerStanding;
}) {
  const copy = gamerStandingCopy(standing, scope);
  const boardRows: BoardRow[] = rows.map((row) => ({
    rank: row.rank,
    profileId: row.profileId,
    displayName: row.displayName,
    avatarUrl: row.avatarUrl,
    username: row.username,
    isMe: row.isMe,
    detail: row.gamesPlayed.toLocaleString("en-US"),
    value: row.wins.toLocaleString("en-US"),
  }));

  return (
    <div>
      <ScopeNav scope={scope} hrefFor={(key) => boardHref({ board: "gamer", window, scope: key })} />
      <WindowNav window={window} hrefFor={(key) => boardHref({ board: "gamer", window: key, scope })} />

      <div className="mt-4">
        <StandingBlock
          ranked={standing.status === "ranked"}
          rank={standing.rank}
          detailLine={copy.detail}
          headline={copy.headline}
          detail={copy.detail}
          value={standing.wins.toLocaleString("en-US")}
          secondary={standing.gamesPlayed.toLocaleString("en-US")}
        />
      </div>

      <div className="mt-6 flex flex-wrap items-baseline justify-between gap-2 type-label text-fg-muted">
        <span>{WINDOW_CAPTION[window]}</span>
        <span>
          {standing.rankedCount.toLocaleString("en-US")} ranked {scope === "friends" ? "on your friends board" : "players"}
        </span>
      </div>

      <BoardList
        rows={boardRows}
        detailLabel="Games"
        valueLabel="Wins"
        empty={
          scope === "friends"
            ? {
                title: "No friends on the board yet",
                body: (
                  <>
                    Add friends to see how you stack up against them. Friends appear after {standing.minWins}{" "}
                    {standing.minWins === 1 ? "win" : "wins"} in this window. <FindFriendsLink />
                  </>
                ),
              }
            : {
                title: "No one is ranked yet",
                body: `Players appear after ${standing.minWins} multiplayer ${standing.minWins === 1 ? "win" : "wins"} in this window.`,
              }
        }
      />

      <p className="mt-5 text-sm leading-6 text-fg-muted">
        A win is a first-place finish in a multiplayer game with at least two players. A tie for first counts as a win for everyone tied.
      </p>
    </div>
  );
}
