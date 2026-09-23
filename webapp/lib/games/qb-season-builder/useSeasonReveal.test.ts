import { act, renderHook } from "@testing-library/react";
import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";

import { REVEAL_STEP_MS, useSeasonReveal } from "./useSeasonReveal";

/**
 * The reveal's order and its one-time-ness, away from the screen that draws it.
 * Same seam as sabotage draft's useTurnReveal and the auction's useLotReveal.
 */

const MATCH = "22222222-2222-2222-2222-222222222222";

const withFakeTimers = async (body: () => Promise<void>) => {
  vi.useFakeTimers({ toFake: ["setTimeout", "clearTimeout"] });
  try {
    await body();
  } finally {
    vi.useRealTimers();
  }
};

const step = async (times = 1) => {
  for (let i = 0; i < times; i += 1) {
    await act(async () => {
      await vi.advanceTimersByTimeAsync(REVEAL_STEP_MS);
    });
  }
};

beforeEach(() => localStorage.clear());
afterEach(() => vi.restoreAllMocks());

describe("a staged reveal", () => {
  it("shows the score first and nothing else", async () => {
    await withFakeTimers(async () => {
      const { result } = renderHook(() => useSeasonReveal(MATCH, true));

      expect(result.current.shows("score")).toBe(true);
      expect(result.current.shows("stat_line")).toBe(false);
      expect(result.current.shows("record")).toBe(false);
      expect(result.current.playing).toBe(true);
    });
  });

  it("advances in the result's top-to-bottom order", async () => {
    await withFakeTimers(async () => {
      const { result } = renderHook(() => useSeasonReveal(MATCH, true));

      await step();
      expect(result.current.shows("stat_line")).toBe(true);
      await step();
      expect(result.current.shows("awards")).toBe(true);
      await step();
      expect(result.current.shows("record")).toBe(true);
      await step();
      expect(result.current.shows("playoffs")).toBe(true);
    });
  });

  it("gives the score a beat of its own before the detail that explains it", async () => {
    await withFakeTimers(async () => {
      const { result } = renderHook(() => useSeasonReveal(MATCH, true));

      await step(4);
      expect(result.current.shows("score")).toBe(true);
      expect(result.current.shows("details")).toBe(false);
      expect(result.current.playing).toBe(true);

      await step();
      expect(result.current.shows("details")).toBe(true);
      expect(result.current.playing).toBe(false);
    });
  });

  it("can be skipped to the end, and then has nothing left to play", async () => {
    await withFakeTimers(async () => {
      const { result } = renderHook(() => useSeasonReveal(MATCH, true));

      act(() => result.current.skip());

      expect(result.current.shows("details")).toBe(true);
      expect(result.current.playing).toBe(false);
    });
  });
});

describe("playing once", () => {
  it("does not replay for a run this browser watched through", async () => {
    await withFakeTimers(async () => {
      const first = renderHook(() => useSeasonReveal(MATCH, true));
      await step(5);
      first.unmount();

      const { result } = renderHook(() => useSeasonReveal(MATCH, true));

      expect(result.current.shows("details")).toBe(true);
      expect(result.current.playing).toBe(false);
    });
  });

  it("does not replay for a run this browser skipped", async () => {
    await withFakeTimers(async () => {
      const first = renderHook(() => useSeasonReveal(MATCH, true));
      act(() => first.result.current.skip());
      first.unmount();

      const { result } = renderHook(() => useSeasonReveal(MATCH, true));

      expect(result.current.playing).toBe(false);
    });
  });

  it("starts over when it was left part-way through", async () => {
    await withFakeTimers(async () => {
      const first = renderHook(() => useSeasonReveal(MATCH, true));
      await step(2);
      first.unmount();

      const { result } = renderHook(() => useSeasonReveal(MATCH, true));

      expect(result.current.shows("record")).toBe(false);
      expect(result.current.playing).toBe(true);
    });
  });

  it("remembers one run without spoiling another", async () => {
    await withFakeTimers(async () => {
      const first = renderHook(() => useSeasonReveal(MATCH, true));
      await step(5);
      first.unmount();

      const { result } = renderHook(() => useSeasonReveal("33333333-3333-3333-3333-333333333333", true));

      expect(result.current.playing).toBe(true);
    });
  });

  it("plays rather than failing when the browser will not remember", async () => {
    await withFakeTimers(async () => {
      vi.spyOn(Storage.prototype, "getItem").mockImplementation(() => { throw new Error("blocked"); });
      vi.spyOn(Storage.prototype, "setItem").mockImplementation(() => { throw new Error("blocked"); });

      const first = renderHook(() => useSeasonReveal(MATCH, true));
      await step(5);
      expect(first.result.current.shows("details")).toBe(true);
      first.unmount();

      const { result } = renderHook(() => useSeasonReveal(MATCH, true));

      expect(result.current.playing).toBe(true);
    });
  });
});

describe("a result nobody is watching land", () => {
  it("is shown whole, with nothing to skip and nothing remembered", async () => {
    await withFakeTimers(async () => {
      const { result } = renderHook(() => useSeasonReveal(MATCH, false));

      expect(result.current.shows("stat_line")).toBe(true);
      expect(result.current.shows("details")).toBe(true);
      expect(result.current.playing).toBe(false);
      // Reading it does not count as having watched the reveal.
      expect(localStorage.getItem(`qb-season-builder:revealed:${MATCH}`)).toBeNull();
    });
  });
});
