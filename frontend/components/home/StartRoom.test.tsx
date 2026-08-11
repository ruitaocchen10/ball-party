import { render, screen } from "@testing-library/react";
import { describe, expect, it, vi } from "vitest";

vi.mock("@/lib/lobbies/actions", () => ({ createLobby: vi.fn() }));

import { StartRoom } from "./StartRoom";

describe("StartRoom", () => {
  it("creates a room for an account holder", () => {
    render(<StartRoom canCreateLobby />);

    expect(screen.getByRole("button", { name: "Start a room" })).toBeInTheDocument();
    expect(screen.queryByRole("link", { name: "Create an account to host" })).not.toBeInTheDocument();
  });

  it("routes a guest or signed-out visitor to account creation", () => {
    render(<StartRoom canCreateLobby={false} />);

    expect(screen.getByRole("link", { name: "Create an account to host" })).toHaveAttribute(
      "href",
      "/signup?next=%2F",
    );
    expect(screen.queryByRole("button", { name: "Start a room" })).not.toBeInTheDocument();
  });
});
