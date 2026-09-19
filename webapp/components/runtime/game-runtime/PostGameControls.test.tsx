import { render, screen } from "@testing-library/react";
import userEvent from "@testing-library/user-event";
import { describe, expect, it, vi } from "vitest";

vi.mock("@/lib/platform/lobbies/actions", () => ({ postGameChoice: vi.fn(async () => undefined) }));

import { postGameChoice } from "@/lib/platform/lobbies/actions";
import { PostGameControls } from "./PostGameControls";

const format = {
  scoringMode: "weekly",
  rosterPreset: "standard",
  qbSlots: 1,
  rbSlots: 1,
  wrSlots: 1,
  teSlots: 1,
  flexSlots: 1,
  purse: 25,
  seasonFrom: 2010,
  seasonTo: 2025,
};

describe("PostGameControls", () => {
  it("lets the host change the replay format before starting the next auction", async () => {
    const user = userEvent.setup();
    render(
      <PostGameControls
        matchId="match"
        roomCode="BLTZ"
        isHost
        format={format}
        era={{ seasonMin: 2010, seasonMax: 2025, minSpan: 4 }}
      />,
    );

    await user.click(screen.getByRole("button", { name: "Replay" }));

    await user.selectOptions(screen.getByRole("combobox", { name: "Scoring" }), "season_total");
    await user.selectOptions(screen.getByRole("combobox", { name: "Roster" }), "deep");
    await user.selectOptions(screen.getByRole("combobox", { name: "First season" }), "2020");
    await user.click(screen.getByRole("button", { name: "Start replay" }));

    expect(postGameChoice).toHaveBeenCalledOnce();
    const submitted = vi.mocked(postGameChoice).mock.calls[0][0];
    expect(submitted).toBeInstanceOf(FormData);
    expect(submitted.get("match_id")).toBe("match");
    expect(submitted.get("choice")).toBe("replay");
    expect(submitted.get("scoring_mode")).toBe("season_total");
    expect(submitted.get("roster_preset")).toBe("deep");
    expect(submitted.get("season_from")).toBe("2020");
    expect(submitted.get("season_to")).toBe("2025");

    expect(screen.getByRole("button", { name: "Back to lobby" })).toBeInTheDocument();
  });

  it("tells players when the host controls the next game", () => {
    render(<PostGameControls matchId="match" roomCode="BLTZ" isHost={false} />);

    expect(screen.getByText("Waiting for the host to choose what’s next.")).toBeInTheDocument();
    expect(screen.queryByRole("button", { name: "Replay" })).not.toBeInTheDocument();
  });
});
