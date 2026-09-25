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
  it("offers a one-click Play solo entry for each solo game, with or without an account", () => {
    render(<SoloGrid />);

    expect(within(card("Higher")).getByRole("button", { name: "Play solo" })).toBeInTheDocument();
    expect(within(card("QB season")).getByRole("button", { name: "Play solo" })).toBeInTheDocument();
    // Auction has no solo floor yet, so it never appears here at all.
    expect(screen.queryAllByRole("button", { name: "Play solo" })).toHaveLength(2);
    expect(screen.queryByText("Auction")).not.toBeInTheDocument();
  });

  it("lets a QB Season Builder run start visible by default or hidden, chosen before it starts", async () => {
    const user = userEvent.setup();
    render(<SoloGrid />);
    const qb = card("QB season");

    expect(within(qb).getByRole("radio", { name: /visible/i })).toBeChecked();
    expect(new FormData(qb.querySelector("form")!).get("mode")).toBe("visible");

    await user.click(within(qb).getByRole("radio", { name: /hidden/i }));
    expect(new FormData(qb.querySelector("form")!).get("mode")).toBe("hidden");
    expect(new FormData(qb.querySelector("form")!).get("game")).toBe("qb_season_builder");
  });

  it("keeps a card's settings collapsed until asked, without dropping them from the form", () => {
    render(<SoloGrid />);
    const qb = card("QB season");
    const settings = qb.querySelector("details")!;

    expect(within(qb).getByText("Settings")).toBeInTheDocument();
    expect(settings).not.toHaveAttribute("open");
    // Shut or not, the defaults still travel with the form.
    expect(new FormData(qb.querySelector("form")!).get("mode")).toBe("visible");
    expect(new FormData(qb.querySelector("form")!).get("era")).toBe("all");
  });

  it("offers Higher or Lower a scoring choice and an era, defaulting to season total over the whole pool", () => {
    render(<SoloGrid higherOrLowerEra={{ seasonMin: 2010, seasonMax: 2024 }} />);
    const hol = card("Higher");
    const form = () => new FormData(hol.querySelector("form")!);

    expect(within(hol).getByText("Settings")).toBeInTheDocument();
    expect(form().get("game")).toBe("higher_or_lower");
    expect(form().get("scoring_mode")).toBe("season_total");
    expect(form().get("season_from")).toBe("2010");
    expect(form().get("season_to")).toBe("2024");
  });

  it("sends Higher or Lower's scoring pick", async () => {
    const user = userEvent.setup();
    render(<SoloGrid higherOrLowerEra={{ seasonMin: 2010, seasonMax: 2024 }} />);
    const hol = card("Higher");

    await user.click(within(hol).getByRole("radio", { name: /weekly/i }));
    expect(new FormData(hol.querySelector("form")!).get("scoring_mode")).toBe("weekly");
  });

  it("still offers scoring, but no era, when the season bounds could not be read", () => {
    render(<SoloGrid />);
    const hol = card("Higher");

    expect(within(hol).getByRole("radio", { name: /weekly/i })).toBeInTheDocument();
    expect(new FormData(hol.querySelector("form")!).get("season_from")).toBeNull();
  });

  it("never says where the ratings come from", () => {
    const { container } = render(<SoloGrid />);

    expect(container).not.toHaveTextContent(/madden|ea sports/i);
  });
});
