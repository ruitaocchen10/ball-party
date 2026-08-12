import { render, screen, within } from "@testing-library/react";
import { describe, expect, it } from "vitest";

import { AuctionScreen } from "./AuctionScreen";
import { SCENARIOS } from "./scenarios";

describe("dev screen smoke", () => {
  it("renders every scenario without throwing", () => {
    for (const scenario of SCENARIOS) {
      const { unmount } = render(
        <AuctionScreen scenario={scenario} remainingMs={(scenario.seconds ?? 0) * 1000} />,
      );
      unmount();
    }
  });

  it("shows the board strip: sold cells with price, current lot, undealt cells", () => {
    const live = SCENARIOS.find((s) => s.id === "your-turn")!;
    render(<AuctionScreen scenario={live} remainingMs={14000} />);

    const board = screen.getByRole("list", { name: "The board" });
    expect(within(board).getAllByRole("listitem")).toHaveLength(20);

    // Lot 6 is settled: it names the slot it filled, the price, and the winner.
    expect(
      within(board).getByLabelText("Lot 6, Derrick Henry, RB, $4, won by Maria"),
    ).toBeInTheDocument();
    // A $0 lot reads as $0, not as an empty cell.
    expect(
      within(board).getByLabelText("Lot 2, Aaron Rodgers, QB, $0, won by Maria"),
    ).toBeInTheDocument();

    // The live lot, and nothing dealt past it.
    expect(within(board).getByText("Lot 7")).toBeInTheDocument();
    expect(within(board).getByLabelText("Lot 8, not yet dealt")).toBeInTheDocument();
    expect(within(board).getByLabelText("Lot 20, not yet dealt")).toBeInTheDocument();
  });

  it("does not name a single undealt player anywhere on the screen", () => {
    const live = SCENARIOS.find((s) => s.id === "your-turn")!;
    render(<AuctionScreen scenario={live} remainingMs={14000} />);
    // Lot 20 is Cooper Kupp in the fixture; nothing on screen may say so.
    expect(screen.queryByText(/Kupp/)).not.toBeInTheDocument();
  });

  it("drops the app chrome in a live match and keeps it on the final screen", () => {
    const live = SCENARIOS.find((s) => s.id === "your-turn")!;
    const { unmount } = render(<AuctionScreen scenario={live} remainingMs={14000} />);
    expect(screen.queryByRole("link", { name: "Ball Party" })).not.toBeInTheDocument();
    unmount();

    const done = SCENARIOS.find((s) => s.finished)!;
    render(<AuctionScreen scenario={done} remainingMs={null} />);
    expect(screen.getByRole("link", { name: "Ball Party" })).toBeInTheDocument();
  });
});
