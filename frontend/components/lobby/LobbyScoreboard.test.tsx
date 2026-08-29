import { render, screen } from "@testing-library/react";
import { describe, expect, it } from "vitest";

import { LobbyScoreboard } from "./LobbyScoreboard";

describe("LobbyScoreboard", () => {
  it("shows every seated player at zero before the first game", () => {
    render(
      <LobbyScoreboard
        members={[
          { user_id: "ava", profiles: { display_name: "Ava" } },
          { user_id: "bo", profiles: { display_name: "Bo" } },
        ]}
        wins={{}}
      />,
    );

    expect(screen.getByRole("list", { name: "" })).toBeInTheDocument();
    expect(screen.getByText("Ava")).toBeInTheDocument();
    expect(screen.getByText("Bo")).toBeInTheDocument();
    expect(screen.getAllByText("0 wins")).toHaveLength(2);
    expect(screen.getByText("First win starts the board.")).toBeInTheDocument();
  });
});
