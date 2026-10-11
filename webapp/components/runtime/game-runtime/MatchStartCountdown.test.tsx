import { act, render, screen } from "@testing-library/react";
import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";

const rpc = vi.fn();
vi.mock("@/lib/supabase/client", () => ({ createClient: () => ({ rpc }) }));

import { MatchStartCountdown } from "./MatchStartCountdown";

const SERVER_NOW = Date.parse("2026-10-11T17:36:13.000Z");
const answer = (seconds: number | null) => ({
  data: {
    play_starts_at: seconds === null ? null : new Date(SERVER_NOW + seconds * 1000).toISOString(),
    server_now: new Date(SERVER_NOW).toISOString(),
  },
  error: null,
});

describe("MatchStartCountdown", () => {
  beforeEach(() => {
    vi.useFakeTimers({ toFake: ["setTimeout", "clearTimeout", "Date"] });
    vi.setSystemTime(SERVER_NOW);
    rpc.mockReset();
  });
  afterEach(() => { vi.useRealTimers(); });

  it("covers the screen with the number and the game while the server's countdown runs", async () => {
    rpc.mockResolvedValue(answer(3));
    render(<MatchStartCountdown matchId="m1" game="auction_team_builder" />);
    await act(async () => { await Promise.resolve(); });

    expect(screen.getByRole("status")).toHaveAccessibleName("Auction Team Builder starts in 3");
    expect(screen.getByText("Starting in")).toBeInTheDocument();
    expect(screen.getByText("Auction Team Builder")).toBeInTheDocument();
  });

  it("goes away once play begins", async () => {
    rpc.mockResolvedValue(answer(3));
    render(<MatchStartCountdown matchId="m1" game="higher_or_lower" />);
    await act(async () => { await Promise.resolve(); });
    await act(async () => { await vi.advanceTimersByTimeAsync(3_500); });

    expect(screen.queryByRole("status")).not.toBeInTheDocument();
  });

  it("renders nothing for a run with no countdown", async () => {
    rpc.mockResolvedValue(answer(null));
    render(<MatchStartCountdown matchId="m1" game="higher_or_lower" />);
    await act(async () => { await Promise.resolve(); });

    expect(screen.queryByRole("status")).not.toBeInTheDocument();
  });
});
