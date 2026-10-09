import { render, screen } from "@testing-library/react";
import userEvent from "@testing-library/user-event";
import { describe, expect, it, vi } from "vitest";

vi.mock("@/lib/platform/lobbies/actions", () => ({ startRun: vi.fn(async () => undefined) }));

import { startRun } from "@/lib/platform/lobbies/actions";
import { StartRun } from "./StartRun";

const era = { seasonMin: 2010, seasonMax: 2025, minSpan: 4 };

/** Opens a themed Select by its label and picks the option with this text. */
async function choose(user: ReturnType<typeof userEvent.setup>, label: string, optionName: string) {
  await user.click(screen.getByRole("combobox", { name: label }));
  await user.click(await screen.findByRole("option", { name: optionName }));
}

describe("StartRun", () => {
  it("submits the host's selected auction format to the start action", async () => {
    const user = userEvent.setup();
    render(<StartRun lobbyId="lobby" code="BLTZ" players={2} era={era} />);

    expect(screen.getByRole("combobox", { name: "Scoring" })).toHaveTextContent("Weekly");
    expect(screen.getByRole("combobox", { name: "Roster" })).toHaveTextContent("Standard · 20 lots");
    expect(screen.getByRole("combobox", { name: "Tokens" })).toHaveTextContent("1 per player");

    await user.click(screen.getByRole("button", { name: "Start the auction" }));

    expect(startRun).toHaveBeenCalledOnce();
    const submitted = vi.mocked(startRun).mock.calls.at(-1)![0];
    expect(submitted).toBeInstanceOf(FormData);
    expect(submitted.get("scoring_mode")).toBe("weekly");
    expect(submitted.get("roster_preset")).toBe("standard");
    expect(submitted.get("token_count")).toBe("1");
  });

  it("offers 0-3 tokens per player and submits the host's selection", async () => {
    const user = userEvent.setup();
    render(<StartRun lobbyId="lobby" code="BLTZ" players={2} era={era} />);

    await choose(user, "Tokens", "Off");
    await user.click(screen.getByRole("button", { name: "Start the auction" }));

    const submitted = vi.mocked(startRun).mock.calls.at(-1)![0];
    expect(submitted.get("token_count")).toBe("0");
  });

  it("offers the longer roster presets and submits the host's selection", async () => {
    const user = userEvent.setup();
    render(<StartRun lobbyId="lobby" code="BLTZ" players={2} era={era} />);

    await user.click(screen.getByRole("combobox", { name: "Roster" }));
    expect(screen.getByRole("option", { name: "Standard · 20 lots" })).toBeInTheDocument();
    expect(screen.getByRole("option", { name: "Full · 28 lots" })).toBeInTheDocument();
    await user.click(screen.getByRole("option", { name: "Deep · 40 lots" }));

    await user.click(screen.getByRole("button", { name: "Start the auction" }));

    const submitted = vi.mocked(startRun).mock.calls.at(-1)![0];
    expect(submitted.get("roster_preset")).toBe("deep");
  });

  it("defaults the era to the whole pool and submits the host's narrowing", async () => {
    const user = userEvent.setup();
    render(<StartRun lobbyId="lobby" code="BLTZ" players={2} era={era} />);

    expect(screen.getByRole("combobox", { name: "First season" })).toHaveTextContent("2010");
    expect(screen.getByRole("combobox", { name: "Last season" })).toHaveTextContent("2025");

    await choose(user, "First season", "2020");
    await user.click(screen.getByRole("button", { name: "Start the auction" }));

    const submitted = vi.mocked(startRun).mock.calls.at(-1)![0];
    expect(submitted.get("season_from")).toBe("2020");
    expect(submitted.get("season_to")).toBe("2025");
  });

  it("refuses a span under the dealer's minimum, and says which rule it broke", async () => {
    const user = userEvent.setup();
    render(<StartRun lobbyId="lobby" code="BLTZ" players={2} era={era} />);

    await choose(user, "First season", "2023");

    expect(screen.getByRole("button", { name: "Start the auction" })).toBeDisabled();
    expect(screen.getByText("Pick a span of at least 4 seasons")).toBeInTheDocument();
  });

  it("refuses a range that runs backwards rather than reordering it", async () => {
    const user = userEvent.setup();
    render(<StartRun lobbyId="lobby" code="BLTZ" players={2} era={era} />);

    await choose(user, "Last season", "2010");
    await choose(user, "First season", "2020");

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
