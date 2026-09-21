import { render, screen, within } from "@testing-library/react";
import userEvent from "@testing-library/user-event";
import { describe, expect, it, vi } from "vitest";

vi.mock("@/lib/platform/lobbies/actions", () => ({ playSolo: vi.fn() }));

import { SoloGrid } from "./SoloGrid";

function card(name: string): HTMLElement {
  const article = screen.getByText(name).closest("article");
  if (!article) throw new Error(`no solo card for ${name}`);
  return article;
}

describe("SoloGrid", () => {
  it("offers a one-click Play solo entry for each solo game to any session, guest included", () => {
    render(<SoloGrid canPlaySolo />);

    expect(within(card("Higher")).getByRole("button", { name: "Play solo" })).toBeInTheDocument();
    expect(within(card("QB season")).getByRole("button", { name: "Play solo" })).toBeInTheDocument();
    // Auction has no solo floor yet, so it never appears here at all.
    expect(screen.queryAllByRole("button", { name: "Play solo" })).toHaveLength(2);
    expect(screen.queryByText("Auction")).not.toBeInTheDocument();
  });

  it("hides Play solo entirely for a visitor with no session at all", () => {
    render(<SoloGrid canPlaySolo={false} />);

    expect(screen.queryByRole("button", { name: "Play solo" })).not.toBeInTheDocument();
    // The games are still named — there is just nothing here yet to act on them.
    expect(screen.getByText("Higher")).toBeInTheDocument();
    expect(screen.getByText("QB season")).toBeInTheDocument();
  });

  it("lets a QB Season Builder run start visible by default or hidden, chosen before it starts", async () => {
    const user = userEvent.setup();
    render(<SoloGrid canPlaySolo />);
    const qb = card("QB season");

    expect(within(qb).getByRole("radio", { name: /visible/i })).toBeChecked();
    expect(new FormData(qb.querySelector("form")!).get("mode")).toBe("visible");

    await user.click(within(qb).getByRole("radio", { name: /hidden/i }));
    expect(new FormData(qb.querySelector("form")!).get("mode")).toBe("hidden");
    expect(new FormData(qb.querySelector("form")!).get("game")).toBe("qb_season_builder");
  });

  it("offers no mode choice on a game that has none", () => {
    render(<SoloGrid canPlaySolo />);

    expect(within(card("Higher")).queryByRole("radio")).not.toBeInTheDocument();
  });

  it("never says where the ratings come from", () => {
    const { container } = render(<SoloGrid canPlaySolo />);

    expect(container).not.toHaveTextContent(/madden|ea sports/i);
  });
});
