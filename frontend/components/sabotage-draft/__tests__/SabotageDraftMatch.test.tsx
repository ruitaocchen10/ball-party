import { render, screen } from "@testing-library/react";
import userEvent from "@testing-library/user-event";
import { beforeEach, describe, expect, it } from "vitest";

import { SabotageDraftMatch } from "@/components/sabotage-draft/SabotageDraftMatch";
import { MATCH, supabaseMock } from "@/test/factories";

const PLAYERS = [
  { match_id: MATCH, user_id: "u0", seat: 0, absent: false, display_name: "Ava" },
  { match_id: MATCH, user_id: "u1", seat: 1, absent: false, display_name: "Ben" },
];

const BOARD = {
  match_id: MATCH,
  round_count: 14,
  current_round: 1,
  slot: "QB",
  turn_deadline: new Date(Date.now() + 30_000).toISOString(),
  server_now: new Date().toISOString(),
  x_factor_open: false,
  active_user_id: "u0",
};

function renderMatch(over: {
  isHost?: boolean;
  paused?: boolean;
  viewerId?: string;
} = {}) {
  return render(
    <SabotageDraftMatch
      matchId={MATCH}
      viewerId={over.viewerId ?? "u0"}
      isHost={over.isHost ?? false}
      paused={over.paused ?? false}
      initial={{
        board: BOARD,
        players: PLAYERS,
        spins: [],
        picks: [],
        statuses: [],
        hits: [],
        guesses: [],
        passes: [],
        decisions: [],
        standings: [],
        tiebreaks: [],
      }}
    />,
  );
}

describe("pausing", () => {
  beforeEach(() => {
    globalThis.__supabaseMock = supabaseMock();
  });

  it("gives only the host a pause control", () => {
    renderMatch({ isHost: false });
    expect(screen.queryByRole("button", { name: "Pause" })).not.toBeInTheDocument();

    renderMatch({ isHost: true });
    expect(screen.getByRole("button", { name: "Pause" })).toBeInTheDocument();
  });

  it("asks the server to pause the match", async () => {
    const user = userEvent.setup();
    renderMatch({ isHost: true });

    await user.click(screen.getByRole("button", { name: "Pause" }));
    expect(globalThis.__supabaseMock.rpc).toHaveBeenCalledWith("pause_match", { p_match_id: MATCH });
  });

  it("shows everybody the paused banner", () => {
    renderMatch({ paused: true });
    expect(screen.getByText("Paused")).toBeInTheDocument();
  });
});
