import { render, screen } from "@testing-library/react";
import { describe, expect, it } from "vitest";

import { LobbyActivity } from "./LobbyActivity";

describe("LobbyActivity", () => {
  it("gives a new room a useful empty state", () => {
    render(<LobbyActivity activity={[]} />);

    expect(screen.getByText("The first game will make the history.")).toBeInTheDocument();
  });

  it("names the winner and game of a completed room match", () => {
    render(<LobbyActivity activity={[{ id: "match-1", game: "higher_or_lower", endedAt: "2026-08-28T12:30:00Z", winnerName: "Ada" }]} />);

    expect(screen.getByText("Ada won Higher or Lower")).toBeInTheDocument();
  });
});
