import { render, screen } from "@testing-library/react";
import { describe, expect, it } from "vitest";

import { SoloBestScores } from "./SoloBestScores";

const score = { game: "Higher or lower", detail: "All-time high", value: "12", rank: 3, rankedCount: 40, href: "/solo/higher-or-lower/leaderboard" };

describe("SoloBestScores", () => {
  it("links each game to its leaderboard and shows the viewer's place", () => {
    render(<SoloBestScores scores={[score]} />);
    expect(screen.getByRole("link", { name: /Higher or lower/ })).toHaveAttribute("href", "/solo/higher-or-lower/leaderboard");
    expect(screen.getByText("#3 of 40")).toBeInTheDocument();
    expect(screen.getByText("12")).toBeInTheDocument();
  });

  it("points an unranked game at its board without a place", () => {
    render(<SoloBestScores scores={[{ ...score, value: null, rank: null, rankedCount: 0 }]} />);
    expect(screen.getByText("—")).toBeInTheDocument();
    expect(screen.getByText("Leaderboard")).toBeInTheDocument();
  });

  it("asks a guest to sign in instead of listing rows", () => {
    render(<SoloBestScores scores={null} />);
    expect(screen.getByRole("link", { name: "Sign in" })).toHaveAttribute("href", "/login?next=/solo");
  });
});
