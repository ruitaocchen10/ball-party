import { render, screen } from "@testing-library/react";
import { describe, expect, it } from "vitest";

import { MemberRoster } from "./MemberRoster";

describe("MemberRoster", () => {
  it("shows an incoming player's visible form in their lineup card", () => {
    render(
      <MemberRoster
        members={[{ user_id: "ada", profiles: { display_name: "Ada" } }]}
        hostId="ada"
        viewerId="ada"
        capacity={1}
        stats={{
          ada: {
            gamesPlayed: 4,
            wins: 3,
            winRate: 75,
            bestStreak: 2,
            recent: [
              { id: "m1", game: "higher_or_lower", endedAt: "2026-08-28T00:00:00Z", placement: 1, rawScore: 10 },
              { id: "m2", game: "higher_or_lower", endedAt: "2026-08-27T00:00:00Z", placement: 2, rawScore: 5 },
            ],
          },
        }}
      />,
    );

    expect(screen.getByLabelText("75% win rate")).toBeInTheDocument();
    expect(screen.getByLabelText("Best streak 2")).toBeInTheDocument();
    expect(screen.getByLabelText("Recent form: win, loss")).toBeInTheDocument();
  });

  it("keeps an empty seat the same minimum height as an occupied card", () => {
    const { container } = render(
      <MemberRoster
        members={[{ user_id: "ada", profiles: { display_name: "Ada" } }]}
        hostId="ada"
        viewerId="ada"
        capacity={2}
        stats={{}}
      />,
    );

    expect(container.querySelector("li > div")?.className).toContain("min-h-64");
    const emptyCard = screen.getByText("Open seat").closest("div");
    expect(emptyCard?.className).toContain("h-full");
    expect(emptyCard?.className).toContain("min-h-64");
  });
});
