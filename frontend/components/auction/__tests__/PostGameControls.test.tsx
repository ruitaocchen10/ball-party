import { render, screen } from "@testing-library/react";
import userEvent from "@testing-library/user-event";
import { describe, expect, it, vi } from "vitest";

vi.mock("@/lib/lobbies/actions", () => ({ postGameChoice: vi.fn(async () => undefined) }));

import { postGameChoice } from "@/lib/lobbies/actions";
import { PostGameControls } from "../PostGameControls";

describe("PostGameControls", () => {
  it("gives the host replay and return-to-lobby choices", async () => {
    const user = userEvent.setup();
    render(<PostGameControls matchId="match" roomCode="BLTZ" isHost />);

    await user.click(screen.getByRole("button", { name: "Replay" }));

    expect(postGameChoice).toHaveBeenCalledOnce();
    const submitted = vi.mocked(postGameChoice).mock.calls[0][0];
    expect(submitted).toBeInstanceOf(FormData);
    expect(submitted.get("match_id")).toBe("match");
    expect(submitted.get("choice")).toBe("replay");

    expect(screen.getByRole("button", { name: "Back to lobby" })).toBeInTheDocument();
  });

  it("tells players when the host controls the next game", () => {
    render(<PostGameControls matchId="match" roomCode="BLTZ" isHost={false} />);

    expect(screen.getByText("Waiting for the host to choose what’s next.")).toBeInTheDocument();
    expect(screen.queryByRole("button", { name: "Replay" })).not.toBeInTheDocument();
  });
});
