import { render, screen } from "@testing-library/react";
import userEvent from "@testing-library/user-event";
import { describe, expect, it, vi } from "vitest";

vi.mock("@/lib/platform/lobbies/actions", () => ({ startRun: vi.fn(async () => undefined) }));

import { startRun } from "@/lib/platform/lobbies/actions";
import { StartWavelength } from "./StartWavelength";

async function choose(user: ReturnType<typeof userEvent.setup>, label: string, optionName: string) {
  await user.click(screen.getByRole("combobox", { name: label }));
  await user.click(await screen.findByRole("option", { name: optionName }));
}

describe("StartWavelength", () => {
  it("offers co-op presets with their round counts and targets", () => {
    render(<StartWavelength lobbyId="lobby" code="BLTZ" players={2} />);

    expect(screen.getByRole("combobox", { name: "Mode" })).toHaveTextContent("Co-op");
    expect(screen.getByRole("combobox", { name: "Game length" })).toHaveTextContent("Short · 4 rounds · target 8");
  });

  it("sends co-op and its selected preset to the start action", async () => {
    const user = userEvent.setup();
    render(<StartWavelength lobbyId="lobby" code="BLTZ" players={2} />);

    await choose(user, "Game length", "Long · 8 rounds · target 20");
    await user.click(screen.getByRole("button", { name: "Start Wavelength" }));

    const submitted = vi.mocked(startRun).mock.calls.at(-1)![0];
    expect(submitted.get("game")).toBe("wavelength_2v2");
    expect(submitted.get("wavelength_mode")).toBe("coop");
    expect(submitted.get("wavelength_preset")).toBe("long");
  });

  it("requires exactly two players for co-op, including a lobby of three", () => {
    render(<StartWavelength lobbyId="lobby" code="BLTZ" players={3} />);

    expect(screen.getByRole("button", { name: "Start Wavelength" })).toBeDisabled();
    expect(screen.getByText("Co-op needs exactly 2 players (you have 3)")).toBeInTheDocument();
  });

  it("requires exactly four players for 2v2 and omits the co-op preset", async () => {
    const user = userEvent.setup();
    render(<StartWavelength lobbyId="lobby" code="BLTZ" players={2} />);

    await choose(user, "Mode", "2v2");

    expect(screen.queryByRole("combobox", { name: "Game length" })).not.toBeInTheDocument();
    expect(screen.getByRole("button", { name: "Start Wavelength" })).toBeDisabled();
    expect(screen.getByText("2v2 needs exactly 4 players (you have 2)")).toBeInTheDocument();
  });

  it("starts 2v2 with four players without a preset", async () => {
    const user = userEvent.setup();
    render(<StartWavelength lobbyId="lobby" code="BLTZ" players={4} />);

    await choose(user, "Mode", "2v2");
    await user.click(screen.getByRole("button", { name: "Start Wavelength" }));

    const submitted = vi.mocked(startRun).mock.calls.at(-1)![0];
    expect(submitted.get("wavelength_mode")).toBe("versus");
    expect(submitted.get("wavelength_preset")).toBeNull();
  });
});
