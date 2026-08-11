import { render, screen } from "@testing-library/react";
import { describe, expect, it, vi } from "vitest";

vi.mock("@/components/lobby/StartRun", () => ({
  StartRun: ({ players }: { players: number }) => <button>Start auction with {players} players</button>,
}));

import { LobbyLineup } from "./LobbyLineup";

describe("LobbyLineup", () => {
  const members = [
    { user_id: "host", profiles: { display_name: "Kayla" } },
    { user_id: "guest", profiles: { display_name: "Devin" } },
  ];

  it("puts the live game alongside honest upcoming games and open seats", () => {
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

    expect(screen.getByRole("heading", { name: /tonight's lineup/i })).toBeInTheDocument();
    expect(screen.getByText(/next up · live/i)).toBeInTheDocument();
    expect(screen.getAllByText(/coming soon/i)).toHaveLength(2);
    expect(screen.getByRole("button", { name: /start auction with 2 players/i })).toBeInTheDocument();
    expect(screen.getAllByText("Invite friend")).toHaveLength(2);

    // The carousel bleeds to the same small-screen gutter as the home page,
    // then becomes the same roomy grid at wider breakpoints.
    const [games, seats] = screen.getAllByRole("list");
    expect(games.className).toContain("-mx-4");
    expect(seats.className).toContain("xl:gap-5");
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
    expect(screen.getByText(/host starts when the party is ready/i)).toBeInTheDocument();
  });
});
