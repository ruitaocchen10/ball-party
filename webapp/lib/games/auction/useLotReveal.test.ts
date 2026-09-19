import { act, renderHook } from "@testing-library/react";
import { describe, expect, it, vi } from "vitest";

import { LOT_REVEAL_MS, useLotReveal } from "./useLotReveal";

const withFakeTimers = async (body: () => Promise<void>) => {
  vi.useFakeTimers({ toFake: ["setTimeout", "clearTimeout"] });
  try {
    await body();
  } finally {
    vi.useRealTimers();
  }
};

const advance = async (ms: number, step = 500) => {
  for (let elapsed = 0; elapsed < ms; elapsed += step) {
    await act(async () => {
      await vi.advanceTimersByTimeAsync(step);
    });
  }
};

describe("the first lot a mount sees", () => {
  it("is revealed immediately, with no artificial wait", async () => {
    await withFakeTimers(async () => {
      const { result } = renderHook(() => useLotReveal("1"));
      expect(result.current.revealed).toBe(true);
    });
  });
});

describe("a lot change", () => {
  it("hides the reveal and restores it after delayMs", async () => {
    await withFakeTimers(async () => {
      const { result, rerender } = renderHook(({ key }: { key: string }) => useLotReveal(key), {
        initialProps: { key: "1" },
      });
      expect(result.current.revealed).toBe(true);

      rerender({ key: "2" });
      expect(result.current.revealed).toBe(false);

      await advance(LOT_REVEAL_MS - 500);
      expect(result.current.revealed).toBe(false);

      await advance(600);
      expect(result.current.revealed).toBe(true);
    });
  });

  it("does nothing when re-rendered with the same key", async () => {
    await withFakeTimers(async () => {
      const { result, rerender } = renderHook(({ key }: { key: string }) => useLotReveal(key), {
        initialProps: { key: "1" },
      });
      rerender({ key: "1" });
      expect(result.current.revealed).toBe(true);
      await advance(LOT_REVEAL_MS + 500);
      expect(result.current.revealed).toBe(true);
    });
  });

  it("uses a caller-supplied delay instead of the default", async () => {
    await withFakeTimers(async () => {
      const { result, rerender } = renderHook(
        ({ key }: { key: string }) => useLotReveal(key, 1_000),
        { initialProps: { key: "1" } },
      );
      rerender({ key: "2" });
      expect(result.current.revealed).toBe(false);

      await advance(900, 100);
      expect(result.current.revealed).toBe(false);

      await advance(200, 100);
      expect(result.current.revealed).toBe(true);
    });
  });
});
