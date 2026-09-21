import { render, screen, within } from "@testing-library/react";
import { describe, expect, it, vi } from "vitest";

vi.mock("@/lib/lobbies/actions", () => ({ createLobby: vi.fn() }));

import { GameGrid } from "./GameGrid";

describe("GameGrid", () => {
  it("advertises Higher or Lower as live while Auction keeps the featured tile", () => {
    render(<GameGrid canCreateLobby />);

    expect(screen.getByText("Group · simultaneous")).toBeInTheDocument();
    expect(screen.getByText("Everyone calls higher or lower at once. Longest streak wins.")).toBeInTheDocument();

    const auctionTile = screen.getByText("Auction").closest("article");
    expect(auctionTile?.parentElement).toHaveClass("lg:col-start-1", "lg:row-span-2", "lg:row-start-1");

    const higherOrLowerTile = screen.getByText("Higher").closest("article");
    expect(higherOrLowerTile?.parentElement).not.toHaveClass("lg:row-span-2");
    expect(within(higherOrLowerTile as HTMLElement).getByText("2–4 players")).toBeInTheDocument();
  });

  it("leaves a solo-only game out of the room grid", () => {
    render(<GameGrid canCreateLobby />);

    expect(screen.queryByText("QB season")).not.toBeInTheDocument();
    expect(screen.queryByText("1 player")).not.toBeInTheDocument();
  });
});
