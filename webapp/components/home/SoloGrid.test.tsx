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
  it("offers a one-click Play entry for each solo game, with or without an account", () => {
    render(<SoloGrid />);

    expect(within(card("Higher")).getByRole("button", { name: "Play" })).toBeInTheDocument();
    expect(within(card("QB season")).getByRole("button", { name: "Play" })).toBeInTheDocument();
    // Auction has no solo floor yet, so it never appears here at all.
    expect(screen.queryAllByRole("button", { name: "Play" })).toHaveLength(2);
    expect(screen.queryByText("Auction")).not.toBeInTheDocument();
  });

  const form = (el: HTMLElement) => new FormData(el.querySelector("form")!);

  async function openSettings(user: ReturnType<typeof userEvent.setup>, el: HTMLElement) {
    await user.click(within(el).getByRole("button", { name: /settings$/i }));
    return screen.getByRole("dialog");
  }

  it("sends each game's defaults with the form without opening settings", () => {
    render(<SoloGrid higherOrLowerEra={{ seasonMin: 2010, seasonMax: 2024 }} />);
    const qb = card("QB season");
    const hol = card("Higher");

    expect(screen.queryByRole("dialog")).not.toBeInTheDocument();
    expect(form(qb).get("game")).toBe("qb_season_builder");
    expect(form(qb).get("mode")).toBe("visible");
    expect(form(qb).get("era")).toBe("all");
    expect(form(hol).get("game")).toBe("higher_or_lower");
    expect(form(hol).get("scoring_mode")).toBe("season_total");
    expect(form(hol).get("season_from")).toBe("2010");
    expect(form(hol).get("season_to")).toBe("2024");
  });

  it("lets a QB Season Builder run start hidden, chosen in the settings dialog and kept after it closes", async () => {
    const user = userEvent.setup();
    render(<SoloGrid />);
    const qb = card("QB season");

    const dialog = await openSettings(user, qb);
    expect(within(dialog).getByRole("radio", { name: /visible/i })).toBeChecked();
    await user.click(within(dialog).getByRole("radio", { name: /hidden/i }));
    await user.click(within(dialog).getByRole("button", { name: "Done" }));

    expect(screen.queryByRole("dialog")).not.toBeInTheDocument();
    expect(form(qb).get("mode")).toBe("hidden");

    const reopened = await openSettings(user, qb);
    expect(within(reopened).getByRole("radio", { name: /hidden/i })).toBeChecked();
  });

  it("sends Higher or Lower's scoring pick", async () => {
    const user = userEvent.setup();
    render(<SoloGrid higherOrLowerEra={{ seasonMin: 2010, seasonMax: 2024 }} />);
    const hol = card("Higher");

    const dialog = await openSettings(user, hol);
    await user.click(within(dialog).getByRole("radio", { name: /weekly/i }));
    expect(form(hol).get("scoring_mode")).toBe("weekly");
  });

  it("still offers Higher or Lower scoring, but no era, when the season bounds could not be read", async () => {
    const user = userEvent.setup();
    render(<SoloGrid />);
    const hol = card("Higher");

    const dialog = await openSettings(user, hol);
    expect(within(dialog).getByRole("radio", { name: /weekly/i })).toBeInTheDocument();
    expect(form(hol).get("season_from")).toBeNull();
  });

  it("never says where the ratings come from", () => {
    const { container } = render(<SoloGrid />);

    expect(container).not.toHaveTextContent(/madden|ea sports/i);
  });
});
