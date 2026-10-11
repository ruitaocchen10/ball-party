import { act, renderHook } from "@testing-library/react";
import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";

const rpc = vi.fn();
vi.mock("@/lib/supabase/client", () => ({ createClient: () => ({ rpc }) }));

import { secondsUntilPlay, useMatchStartCountdown, type MatchPlayStart } from "./useMatchStartCountdown";

const SERVER_NOW = Date.parse("2026-10-11T17:36:13.000Z");
const startingIn = (seconds: number): MatchPlayStart => ({
  play_starts_at: new Date(SERVER_NOW + seconds * 1000).toISOString(),
  server_now: new Date(SERVER_NOW).toISOString(),
});

describe("secondsUntilPlay", () => {
  it("counts down to the server's start time", () => {
    expect(secondsUntilPlay(startingIn(3), 5_000, 5_000)).toBeCloseTo(3);
    expect(secondsUntilPlay(startingIn(3), 5_000, 6_250)).toBeCloseTo(1.75);
    expect(secondsUntilPlay(startingIn(3), 5_000, 8_000)).toBeCloseTo(0);
  });

  it("shows a late joiner only what is left", () => {
    expect(secondsUntilPlay(startingIn(1.2), 9_999, 9_999)).toBeCloseTo(1.2);
  });

  it("ignores what the device thinks the time is", () => {
    // Only the time elapsed since the fetch counts, not the absolute clock.
    expect(secondsUntilPlay(startingIn(3), 42, 1_042)).toBeCloseTo(2);
  });

  it("has nothing to count when the match has no start time", () => {
    expect(secondsUntilPlay({ play_starts_at: null, server_now: new Date(SERVER_NOW).toISOString() }, 0, 0)).toBeNull();
  });
});

describe("useMatchStartCountdown", () => {
  beforeEach(() => {
    vi.useFakeTimers({ toFake: ["setTimeout", "clearTimeout", "Date"] });
    vi.setSystemTime(SERVER_NOW);
    rpc.mockReset();
  });
  afterEach(() => { vi.useRealTimers(); });

  const settle = () => act(async () => { await Promise.resolve(); });
  const advance = (ms: number) => act(async () => { await vi.advanceTimersByTimeAsync(ms); });

  it("counts 3, 2, 1 and then clears", async () => {
    rpc.mockResolvedValue({ data: startingIn(3), error: null });
    const { result } = renderHook(() => useMatchStartCountdown("m1"));
    await settle();

    expect(rpc).toHaveBeenCalledWith("match_play_start", { p_match_id: "m1" });
    expect(result.current).toBe(3);
    await advance(1_000);
    expect(result.current).toBe(2);
    await advance(1_000);
    expect(result.current).toBe(1);
    await advance(1_000);
    expect(result.current).toBeNull();
  });

  it("picks up partway through for someone who opens the match late", async () => {
    rpc.mockResolvedValue({ data: startingIn(1.4), error: null });
    const { result } = renderHook(() => useMatchStartCountdown("m1"));
    await settle();

    expect(result.current).toBe(2);
    await advance(500);
    expect(result.current).toBe(1);
  });

  it("shows nothing for a run with no countdown", async () => {
    rpc.mockResolvedValue({ data: { play_starts_at: null, server_now: new Date(SERVER_NOW).toISOString() }, error: null });
    const { result } = renderHook(() => useMatchStartCountdown("m1"));
    await settle();

    expect(result.current).toBeNull();
  });

  it("shows nothing when the read fails, since the match is already running", async () => {
    rpc.mockResolvedValue({ data: null, error: { message: "boom" } });
    const { result } = renderHook(() => useMatchStartCountdown("m1"));
    await settle();

    expect(result.current).toBeNull();
  });
});
