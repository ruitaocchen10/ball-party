import { render, screen } from "@testing-library/react";
import { describe, expect, it } from "vitest";

import { GamerLeaderboard } from "./GamerLeaderboard";
import { SoloLeaderboard } from "./SoloLeaderboard";

const unrankedGamer = { status: "unranked", rank: null, wins: 0, gamesPlayed: 0, rankedCount: 0, minWins: 1 } as const;
const unrankedSolo = { status: "unranked", rank: null, bestScore: null, rankedCount: 0 } as const;

describe("GamerLeaderboard", () => {
  it("keeps the board in window and scope links", () => {
    render(<GamerLeaderboard window="month" scope="friends" rows={[]} standing={unrankedGamer} />);
    expect(screen.getByRole("link", { name: "Everyone" })).toHaveAttribute("href", "/leaderboard?board=gamer&window=month");
    expect(screen.getByRole("link", { name: "Year" })).toHaveAttribute("href", "/leaderboard?board=gamer&window=year&scope=friends");
  });

  it("shows wins and games, and links a row only when it carries a username", () => {
    const row = { rank: 1, profileId: "p1", displayName: "Ava", avatarUrl: null, wins: 12, gamesPlayed: 30, isMe: false };
    render(
      <GamerLeaderboard
        window="week"
        rows={[{ ...row, username: "ava" }, { ...row, profileId: "p2", rank: 2, displayName: "Ben", wins: 3, gamesPlayed: 7 }]}
        standing={unrankedGamer}
      />,
    );
    expect(screen.getByRole("link", { name: "Ava" })).toHaveAttribute("href", "/u/ava");
    expect(screen.queryByRole("link", { name: "Ben" })).not.toBeInTheDocument();
    expect(screen.getByText("12")).toBeInTheDocument();
    expect(screen.getByText("30")).toBeInTheDocument();
    expect(screen.getByText("7")).toBeInTheDocument();
  });

  it("says why the caller is not ranked, and has a friends empty state", () => {
    render(<GamerLeaderboard window="week" scope="friends" rows={[]} standing={unrankedGamer} />);
    expect(screen.getByText("Not ranked yet")).toBeInTheDocument();
    expect(screen.getByText("No friends on the board yet")).toBeInTheDocument();
    expect(screen.getByRole("link", { name: "Find friends" })).toHaveAttribute("href", "/friends");
  });
});

describe("SoloLeaderboard", () => {
  it("offers a Visible / Hidden toggle on QB Season Builder only", () => {
    const { unmount } = render(<SoloLeaderboard board="qb-season-builder" mode="visible" rows={[]} standing={unrankedSolo} />);
    expect(screen.getByRole("link", { name: "Hidden" })).toHaveAttribute("href", "/solo/qb-season-builder/leaderboard?mode=hidden");
    unmount();

    render(<SoloLeaderboard board="higher-or-lower" rows={[]} standing={unrankedSolo} />);
    expect(screen.queryByRole("navigation", { name: "Season mode" })).not.toBeInTheDocument();
  });

  it("keeps the mode when switching scope", () => {
    render(<SoloLeaderboard board="qb-season-builder" mode="hidden" rows={[]} standing={unrankedSolo} />);
    expect(screen.getByRole("link", { name: "Friends" })).toHaveAttribute("href", "/solo/qb-season-builder/leaderboard?scope=friends&mode=hidden");
  });

  it("formats a QB score with one decimal", () => {
    const row = { rank: 1, profileId: "p1", displayName: "Ava", avatarUrl: null, bestScore: 91, isMe: false };
    render(<SoloLeaderboard board="qb-season-builder" mode="visible" rows={[row]} standing={unrankedSolo} />);
    expect(screen.getByText("91.0")).toBeInTheDocument();
  });
});
