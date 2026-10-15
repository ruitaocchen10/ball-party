import { render, screen } from "@testing-library/react";
import { describe, expect, it } from "vitest";

import { BallKnowerLeaderboard } from "./BallKnowerLeaderboard";

const unranked = { status: "unranked", rank: null, totalPoints: 0, scoredPicks: 0, rankedCount: 0, minPicks: 5 } as const;

describe("BallKnowerLeaderboard scope toggle", () => {
  it("marks the active scope and keeps the window when switching", () => {
    render(<BallKnowerLeaderboard window="month" scope="friends" rows={[]} standing={unranked} />);

    const scope = screen.getByRole("navigation", { name: "Leaderboard scope" });
    expect(scope.querySelector('[aria-current="page"]')).toHaveTextContent("Friends");
    expect(screen.getByRole("link", { name: "Everyone" })).toHaveAttribute("href", "/leaderboard?window=month");
  });

  it("keeps the scope when switching windows", () => {
    render(<BallKnowerLeaderboard window="week" scope="friends" rows={[]} standing={unranked} />);
    expect(screen.getByRole("link", { name: "Year" })).toHaveAttribute("href", "/leaderboard?window=year&scope=friends");
  });

  it("points an empty friends board at the profile Friends tab", () => {
    render(<BallKnowerLeaderboard window="week" scope="friends" rows={[]} standing={unranked} />);
    expect(screen.getByText("No friends on the board yet")).toBeInTheDocument();
    expect(screen.getByRole("link", { name: "Find friends" })).toHaveAttribute("href", "/friends");
  });

  it("keeps the global empty copy on the everyone board", () => {
    render(<BallKnowerLeaderboard window="week" rows={[]} standing={unranked} />);
    expect(screen.getByText("No one is ranked yet")).toBeInTheDocument();
  });

  it("links a row to the profile only when it carries a username", () => {
    const row = { rank: 1, profileId: "p1", displayName: "Ava", avatarUrl: null, totalPoints: 10, scoredPicks: 6, isMe: false };
    render(
      <BallKnowerLeaderboard
        window="week"
        rows={[{ ...row, username: "ava" }, { ...row, profileId: "p2", rank: 2, displayName: "Ben" }]}
        standing={unranked}
      />,
    );
    expect(screen.getByRole("link", { name: "Ava" })).toHaveAttribute("href", "/u/ava");
    expect(screen.queryByRole("link", { name: "Ben" })).not.toBeInTheDocument();
    expect(screen.getByText("Ben")).toBeInTheDocument();
  });
});
