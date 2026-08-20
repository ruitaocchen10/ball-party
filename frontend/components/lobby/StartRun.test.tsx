import { render, screen } from "@testing-library/react";
import userEvent from "@testing-library/user-event";
import { describe, expect, it, vi } from "vitest";

vi.mock("@/lib/lobbies/actions", () => ({ startRun: vi.fn(async () => undefined) }));

import { startRun } from "@/lib/lobbies/actions";
import { StartRun } from "./StartRun";

const era = { seasonMin: 2010, seasonMax: 2025, minSpan: 1 };

describe("StartRun", () => {
  it("submits the host's selected auction format to the start action", async () => {
    const user = userEvent.setup();
    render(<StartRun lobbyId="lobby" code="BLTZ" players={2} era={era} />);

    expect(screen.getByRole("combobox", { name: "Scoring" })).toHaveValue("season_total");
    expect(screen.getByRole("combobox", { name: "Roster" })).toHaveValue("standard");
    expect(screen.getByRole("combobox", { name: "Scoring" })).toHaveAttribute("name", "scoring_mode");
    expect(screen.getByRole("combobox", { name: "Roster" })).toHaveAttribute("name", "roster_preset");

    await user.click(screen.getByRole("button", { name: "Start the auction" }));

    expect(startRun).toHaveBeenCalledOnce();
    const submitted = vi.mocked(startRun).mock.calls.at(-1)![0];
    expect(submitted).toBeInstanceOf(FormData);
    expect(submitted.get("scoring_mode")).toBe("season_total");
    expect(submitted.get("roster_preset")).toBe("standard");
  });

  it("offers the longer roster presets and submits the host's selection", async () => {
    const user = userEvent.setup();
    render(<StartRun lobbyId="lobby" code="BLTZ" players={2} era={era} />);

    const roster = screen.getByRole("combobox", { name: "Roster" });
    expect(roster).toHaveTextContent("Standard · 20 lots");
    expect(roster).toHaveTextContent("Full · 28 lots");
    expect(roster).toHaveTextContent("Deep · 40 lots");

    await user.selectOptions(roster, "deep");
    await user.click(screen.getByRole("button", { name: "Start the auction" }));

    const submitted = vi.mocked(startRun).mock.calls.at(-1)![0];
    expect(submitted.get("roster_preset")).toBe("deep");
  });

  it("defaults the era to the whole pool and submits the host's narrowing", async () => {
    const user = userEvent.setup();
    render(<StartRun lobbyId="lobby" code="BLTZ" players={2} era={era} />);

    expect(screen.getByRole("combobox", { name: "First season" })).toHaveValue("2010");
    expect(screen.getByRole("combobox", { name: "Last season" })).toHaveValue("2025");

    await user.selectOptions(screen.getByRole("combobox", { name: "First season" }), "2020");
    await user.click(screen.getByRole("button", { name: "Start the auction" }));

    const submitted = vi.mocked(startRun).mock.calls.at(-1)![0];
    expect(submitted.get("season_from")).toBe("2020");
    expect(submitted.get("season_to")).toBe("2025");
  });

  it("allows a single-season era", async () => {
    const user = userEvent.setup();
    render(<StartRun lobbyId="lobby" code="BLTZ" players={2} era={era} />);

    await user.selectOptions(screen.getByRole("combobox", { name: "First season" }), "2025");

    expect(screen.getByRole("button", { name: "Start the auction" })).toBeEnabled();
    await user.click(screen.getByRole("button", { name: "Start the auction" }));

    const submitted = vi.mocked(startRun).mock.calls.at(-1)![0];
    expect(submitted.get("season_from")).toBe("2025");
    expect(submitted.get("season_to")).toBe("2025");
  });

  it("refuses a range that runs backwards rather than reordering it", async () => {
    const user = userEvent.setup();
    render(<StartRun lobbyId="lobby" code="BLTZ" players={2} era={era} />);

    await user.selectOptions(screen.getByRole("combobox", { name: "Last season" }), "2010");
    await user.selectOptions(screen.getByRole("combobox", { name: "First season" }), "2020");

    expect(screen.getByRole("button", { name: "Start the auction" })).toBeDisabled();
    expect(screen.getByText("The last season has to come after the first")).toBeInTheDocument();
  });

  // The bounds are read from the pool at request time, so the picker has to
  // survive not getting them. Sending no range is what every board was dealt
  // with before the era was a choice.
  it("omits the era entirely when the bounds could not be read", async () => {
    const user = userEvent.setup();
    render(<StartRun lobbyId="lobby" code="BLTZ" players={2} era={null} />);

    expect(screen.queryByRole("combobox", { name: "First season" })).not.toBeInTheDocument();

    await user.click(screen.getByRole("button", { name: "Start the auction" }));

    const submitted = vi.mocked(startRun).mock.calls.at(-1)![0];
    expect(submitted.get("season_from")).toBeNull();
    expect(submitted.get("season_to")).toBeNull();
  });
});
