import { render, screen } from "@testing-library/react";
import userEvent from "@testing-library/user-event";
import { describe, expect, it, vi } from "vitest";

vi.mock("@/lib/lobbies/actions", () => ({ startRun: vi.fn(async () => undefined) }));

import { startRun } from "@/lib/lobbies/actions";
import { StartRun } from "./StartRun";

describe("StartRun", () => {
  it("submits the host's selected auction format to the start action", async () => {
    const user = userEvent.setup();
    render(<StartRun lobbyId="lobby" code="BLTZ" players={2} />);

    expect(screen.getByRole("combobox", { name: "Scoring" })).toHaveValue("weekly");
    expect(screen.getByRole("combobox", { name: "Roster" })).toHaveValue("standard");
    expect(screen.getByRole("combobox", { name: "Scoring" })).toHaveAttribute("name", "scoring_mode");
    expect(screen.getByRole("combobox", { name: "Roster" })).toHaveAttribute("name", "roster_preset");

    await user.click(screen.getByRole("button", { name: "Start the auction" }));

    expect(startRun).toHaveBeenCalledOnce();
    const submitted = vi.mocked(startRun).mock.calls.at(-1)![0];
    expect(submitted).toBeInstanceOf(FormData);
    expect(submitted.get("scoring_mode")).toBe("weekly");
    expect(submitted.get("roster_preset")).toBe("standard");
  });

  it("offers the longer roster presets and submits the host's selection", async () => {
    const user = userEvent.setup();
    render(<StartRun lobbyId="lobby" code="BLTZ" players={2} />);

    const roster = screen.getByRole("combobox", { name: "Roster" });
    expect(roster).toHaveTextContent("Standard · 20 lots");
    expect(roster).toHaveTextContent("Full · 28 lots");
    expect(roster).toHaveTextContent("Deep · 40 lots");

    await user.selectOptions(roster, "deep");
    await user.click(screen.getByRole("button", { name: "Start the auction" }));

    const submitted = vi.mocked(startRun).mock.calls.at(-1)![0];
    expect(submitted.get("roster_preset")).toBe("deep");
  });
});
