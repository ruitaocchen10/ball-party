import { render, screen } from "@testing-library/react";
import { describe, expect, it, vi } from "vitest";

vi.mock("@/lib/lobbies/actions", () => ({ createLobby: vi.fn(), playSolo: vi.fn() }));

import { GameGrid } from "./GameGrid";

describe("GameGrid", () => {
  it("advertises Higher or Lower as live while Auction keeps the featured tile", () => {
    render(<GameGrid canCreateLobby canPlaySolo={false} />);

    expect(screen.getByText("Group · simultaneous")).toBeInTheDocument();
    expect(screen.getByText("Everyone calls higher or lower at once. Longest streak wins.")).toBeInTheDocument();
    expect(screen.getByText("2–4 players · 3–5 min")).toBeInTheDocument();

    const auctionTile = screen.getByText("Auction").closest("article");
    expect(auctionTile?.parentElement).toHaveClass("lg:col-start-1", "lg:row-span-2", "lg:row-start-1");

    const higherOrLowerTile = screen.getByText("Higher").closest("article");
    expect(higherOrLowerTile?.parentElement).not.toHaveClass("lg:row-span-2");
  });

  it("offers a one-click Play solo entry for Higher or Lower to any session, guest included", () => {
    render(<GameGrid canCreateLobby={false} canPlaySolo />);

    expect(screen.getByRole("button", { name: "Play solo" })).toBeInTheDocument();
    // Auction has no solo floor yet, so it keeps the single account-gated action.
    expect(screen.queryAllByRole("button", { name: "Play solo" })).toHaveLength(1);
  });

  it("hides Play solo entirely for a visitor with no session at all", () => {
    render(<GameGrid canCreateLobby={false} canPlaySolo={false} />);

    expect(screen.queryByRole("button", { name: "Play solo" })).not.toBeInTheDocument();
  });
});
