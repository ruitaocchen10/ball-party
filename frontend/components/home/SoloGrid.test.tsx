import { render, screen } from "@testing-library/react";
import { describe, expect, it, vi } from "vitest";

vi.mock("@/lib/lobbies/actions", () => ({ playSolo: vi.fn() }));

import { SoloGrid } from "./SoloGrid";

describe("SoloGrid", () => {
  it("offers a one-click Play solo entry for Higher or Lower to any session, guest included", () => {
    render(<SoloGrid canPlaySolo />);

    expect(screen.getByRole("button", { name: "Play solo" })).toBeInTheDocument();
    // Auction has no solo floor yet, so it never appears here at all.
    expect(screen.queryAllByRole("button", { name: "Play solo" })).toHaveLength(1);
    expect(screen.queryByText("Auction")).not.toBeInTheDocument();
  });

  it("hides Play solo entirely for a visitor with no session at all", () => {
    render(<SoloGrid canPlaySolo={false} />);

    expect(screen.queryByRole("button", { name: "Play solo" })).not.toBeInTheDocument();
    // The game is still named — there is just nothing here yet to act on it.
    expect(screen.getByText("Higher")).toBeInTheDocument();
  });
});
