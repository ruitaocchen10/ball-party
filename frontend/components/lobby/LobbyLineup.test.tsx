import { render, screen, within } from "@testing-library/react";
import { describe, expect, it, vi } from "vitest";

vi.mock("@/components/lobby/StartRun", () => ({
  StartRun: ({ players }: { players: number }) => <button>Start auction with {players} players</button>,
}));

vi.mock("@/components/lobby/StartHigherOrLower", () => ({
  StartHigherOrLower: ({ players }: { players: number }) => (
    <button>Start higher or lower with {players} players</button>
  ),
}));

import { LobbyLineup } from "./LobbyLineup";

describe("LobbyLineup", () => {
  const members = [
    { user_id: "host", profiles: { display_name: "Kayla" } },
    { user_id: "guest", profiles: { display_name: "Devin", is_guest: true } },
  ];

  it("centers the party table before the games and keeps the game catalogue honest", () => {
    render(
      <LobbyLineup
        lobbyId="lobby"
        code="BLTZ"
        members={members}
        hostId="host"
        viewerId="host"
        isHost
        inFlight={false}
      />,
    );

    expect(screen.getByRole("heading", { name: /your party/i })).toBeInTheDocument();
    expect(screen.getByRole("heading", { name: /choose the next game/i })).toBeInTheDocument();
    expect(screen.getAllByText(/next up · live/i)).toHaveLength(3);
    expect(screen.queryByText(/next up · in development/i)).not.toBeInTheDocument();
    expect(screen.getAllByText(/coming soon/i)).toHaveLength(1);
    const higherOrLowerTile = screen
      .getByText("Everyone calls higher or lower at once. Longest streak wins.")
      .closest("article, div");
    expect(within(higherOrLowerTile as HTMLElement).getByText("2–4 players")).toBeInTheDocument();
    expect(screen.getByRole("button", { name: /start auction with 2 players/i })).toBeInTheDocument();
    expect(
      screen.getByRole("button", { name: /start higher or lower with 2 players/i }),
    ).toBeInTheDocument();
    expect(screen.getAllByText("Invite a friend")).toHaveLength(2);
    expect(screen.getAllByText("Open seat")).toHaveLength(2);
    expect(screen.getByText(/guest/i)).toBeInTheDocument();

    // The carousel bleeds to the same small-screen gutter as the home page,
    // then becomes the same roomy grid at wider breakpoints.
    const [roster, gameCarousel] = screen.getAllByRole("list");
    expect(roster).toHaveAccessibleName("Players at the table");
    expect(gameCarousel.className).toContain("-mx-4");
  });

  it("does not offer a start control to a guest", () => {
    render(
      <LobbyLineup
        lobbyId="lobby"
        code="BLTZ"
        members={members}
        hostId="host"
        viewerId="guest"
        isHost={false}
        inFlight={false}
      />,
    );

    expect(screen.queryByRole("button", { name: /start auction/i })).not.toBeInTheDocument();
    expect(screen.queryByRole("button", { name: /start higher or lower/i })).not.toBeInTheDocument();
    expect(screen.getByText(/host picks the next game when the party is ready/i)).toBeInTheDocument();
  });
});
