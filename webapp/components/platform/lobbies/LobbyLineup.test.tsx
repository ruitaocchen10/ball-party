import { render, screen } from "@testing-library/react";
import { describe, expect, it } from "vitest";

import { LobbyLineup } from "./LobbyLineup";

describe("LobbyLineup", () => {
  const members = [
    { user_id: "host", profiles: { display_name: "Kayla" } },
    { user_id: "guest", profiles: { display_name: "Devin", is_guest: true } },
  ];

  it("renders the party's roster with open seats", () => {
    render(<LobbyLineup members={members} hostId="host" viewerId="host" />);

    expect(screen.getByRole("heading", { name: /your party/i })).toBeInTheDocument();
    expect(screen.getByText("2 of 4 seats")).toBeInTheDocument();
    expect(screen.getAllByText("Invite a friend")).toHaveLength(2);
    expect(screen.getAllByText("Open seat")).toHaveLength(2);
    expect(screen.getByText(/playing now/i)).toBeInTheDocument();

    const roster = screen.getByRole("list", { name: "Players at the table" });
    expect(roster).toBeInTheDocument();
  });
});
