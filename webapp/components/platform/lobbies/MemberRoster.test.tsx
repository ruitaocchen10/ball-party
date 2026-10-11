import { render, screen } from "@testing-library/react";
import userEvent from "@testing-library/user-event";
import { describe, expect, it, vi } from "vitest";

// The invite dialog reads the viewer's friends when it opens.
vi.mock("@/lib/supabase/client", () => ({
  createClient: () => ({ rpc: async () => ({ data: [], error: null }) }),
}));

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

  it("marks the host and the viewer on their light cards", () => {
    render(
      <MemberRoster
        members={[
          { user_id: "ada", profiles: { display_name: "Ada" } },
          { user_id: "bo", profiles: { display_name: "Bo" } },
        ]}
        hostId="ada"
        viewerId="bo"
        capacity={2}
        stats={{}}
      />,
    );

    expect(screen.getAllByText("Host")).toHaveLength(1);
    expect(screen.getByText("you")).toBeInTheDocument();
    expect(screen.getByText("at the table")).toBeInTheDocument();
  });

  it("opens the invite dialog from an open seat", async () => {
    const user = userEvent.setup();
    render(
      <MemberRoster
        members={[{ user_id: "ada", profiles: { display_name: "Ada" } }]}
        hostId="ada"
        viewerId="ada"
        capacity={2}
        stats={{}}
        lobbyId="lobby-1"
      />,
    );

    expect(screen.queryByText("Invite friends")).not.toBeInTheDocument();
    await user.click(screen.getByRole("button", { name: /open seat/i }));
    expect(await screen.findByText("Invite friends")).toBeInTheDocument();
  });

  it("leaves an open seat as a plain marker when there is no room to invite to", () => {
    render(
      <MemberRoster members={[]} hostId="ada" viewerId="ada" capacity={1} stats={{}} />,
    );

    expect(screen.queryByRole("button", { name: /open seat/i })).not.toBeInTheDocument();
    expect(screen.getByText("Open seat")).toBeInTheDocument();
  });
});
