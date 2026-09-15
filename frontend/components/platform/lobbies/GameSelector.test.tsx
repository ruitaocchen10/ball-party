import { render, screen } from "@testing-library/react";
import userEvent from "@testing-library/user-event";
import { describe, expect, it, vi } from "vitest";

vi.mock("@/lib/platform/lobbies/actions", () => ({ selectGame: vi.fn(async () => undefined) }));
vi.mock("@/components/platform/lobbies/StartRun", () => ({
  StartRun: ({ players }: { players: number }) => <button>Start auction with {players} players</button>,
}));
vi.mock("@/components/platform/lobbies/StartHigherOrLower", () => ({
  StartHigherOrLower: ({ players }: { players: number }) => (
    <button>Start higher or lower with {players} players</button>
  ),
}));
vi.mock("@/components/platform/lobbies/StartSabotageDraft", () => ({
  StartSabotageDraft: ({ players }: { players: number }) => (
    <button>Start sabotage draft with {players} players</button>
  ),
}));

import { selectGame } from "@/lib/platform/lobbies/actions";
import { GameSelector } from "./GameSelector";

describe("GameSelector", () => {
  it("opens straight to the picker when nothing has been chosen yet", () => {
    render(
      <GameSelector
        lobbyId="lobby"
        code="BLTZ"
        isHost
        inFlight={false}
        selectedGame={null}
        players={2}
      />,
    );

    expect(screen.getByRole("heading", { name: "Choose a game" })).toBeInTheDocument();
    expect(screen.getByRole("button", { name: /sabotage/i })).toBeInTheDocument();
    expect(screen.getByRole("button", { name: /higher or lower/i })).toBeInTheDocument();
    expect(screen.getByRole("button", { name: /auction/i })).toBeInTheDocument();
  });

  it("submits the chosen game to the select action", async () => {
    const user = userEvent.setup();
    render(
      <GameSelector
        lobbyId="lobby"
        code="BLTZ"
        isHost
        inFlight={false}
        selectedGame={null}
        players={2}
      />,
    );

    await user.click(screen.getByRole("button", { name: /higher or lower/i }));

    expect(selectGame).toHaveBeenCalledOnce();
    const submitted = vi.mocked(selectGame).mock.calls.at(-1)![0];
    expect(submitted.get("lobby_id")).toBe("lobby");
    expect(submitted.get("game")).toBe("higher_or_lower");
  });

  it("shows the selected game's start control to the host", () => {
    render(
      <GameSelector
        lobbyId="lobby"
        code="BLTZ"
        isHost
        inFlight={false}
        selectedGame="sabotage_draft"
        players={2}
      />,
    );

    expect(screen.getByRole("heading", { name: "Sabotage draft" })).toBeInTheDocument();
    expect(screen.getByRole("button", { name: /start sabotage draft with 2 players/i })).toBeInTheDocument();
    expect(screen.getByRole("button", { name: "Change game" })).toBeInTheDocument();
  });

  it("hides the start control and the change option while a match is in flight", () => {
    render(
      <GameSelector
        lobbyId="lobby"
        code="BLTZ"
        isHost
        inFlight
        selectedGame="sabotage_draft"
        players={2}
      />,
    );

    expect(screen.queryByRole("button", { name: /start sabotage draft/i })).not.toBeInTheDocument();
    expect(screen.queryByRole("button", { name: "Change game" })).not.toBeInTheDocument();
  });

  it("gives a non-host viewer no start or change controls", () => {
    render(
      <GameSelector
        lobbyId="lobby"
        code="BLTZ"
        isHost={false}
        inFlight={false}
        selectedGame="higher_or_lower"
        players={2}
      />,
    );

    expect(screen.getByRole("heading", { name: "Higher or lower" })).toBeInTheDocument();
    expect(screen.queryByRole("button", { name: /start higher or lower/i })).not.toBeInTheDocument();
    expect(screen.queryByRole("button", { name: "Change game" })).not.toBeInTheDocument();
    expect(screen.getByText("Waiting for the host to start")).toBeInTheDocument();
  });

  it("tells a non-host viewer when the host has not picked a game", () => {
    render(
      <GameSelector
        lobbyId="lobby"
        code="BLTZ"
        isHost={false}
        inFlight={false}
        selectedGame={null}
        players={2}
      />,
    );

    expect(screen.getByText("The host hasn't picked a game yet.")).toBeInTheDocument();
  });

  it("lets the host reopen the picker to change the selection", async () => {
    const user = userEvent.setup();
    render(
      <GameSelector
        lobbyId="lobby"
        code="BLTZ"
        isHost
        inFlight={false}
        selectedGame="sabotage_draft"
        players={2}
      />,
    );

    await user.click(screen.getByRole("button", { name: "Change game" }));

    expect(screen.getByRole("heading", { name: "Choose a game" })).toBeInTheDocument();
    expect(screen.getByRole("button", { name: "Cancel" })).toBeInTheDocument();
  });
});
