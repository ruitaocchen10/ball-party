import { act, renderHook, waitFor } from "@testing-library/react";
import { describe, expect, it, vi } from "vitest";

import { HEARTBEAT_MS, useMatchClock, VISIBLE_SLACK_MS } from "./useMatchClock";

/**
 * The behaviours in isolation, the same ones the auction's match-screen suite
 * exercises through a whole component. Fake timers throughout: Date has to be
 * faked alongside the interval, since the hook derives `now` from Date.now()
 * plus a measured offset, and a fake interval driving a real clock would
 * advance the ticks without advancing the time they read.
 */

const NOW = Date.parse("2026-08-15T12:00:00.000Z");

const withFakeTimers = async (body: () => Promise<void>) => {
  vi.useFakeTimers({ toFake: ["setInterval", "clearInterval", "setTimeout", "clearTimeout", "Date"] });
  vi.setSystemTime(NOW);
  try {
    await body();
  } finally {
    vi.useRealTimers();
  }
};

/** Advances in steps rather than one jump, so effects see every tick rather
 *  than only the final value. */
const advance = async (ms: number, step = 500) => {
  for (let elapsed = 0; elapsed < ms; elapsed += step) {
    await act(async () => {
      await vi.advanceTimersByTimeAsync(step);
    });
  }
};

const iso = (offsetMs: number) => new Date(NOW + offsetMs).toISOString();

describe("the countdown", () => {
  it("counts down to the deadline unmodified when no slack is requested", async () => {
    await withFakeTimers(async () => {
      const { result } = renderHook(() =>
        useMatchClock({
          serverNow: iso(0),
          deadline: iso(10_000),
          expire: vi.fn(),
          reconcile: vi.fn(),
        }),
      );
      await advance(0);
      expect(result.current.remainingMs).toBe(10_000);
    });
  });

  it("ends slightly before the real deadline when the caller asks for slack", async () => {
    await withFakeTimers(async () => {
      const { result } = renderHook(() =>
        useMatchClock({
          serverNow: iso(0),
          deadline: iso(10_000),
          visibleSlackMs: VISIBLE_SLACK_MS,
          expire: vi.fn(),
          reconcile: vi.fn(),
        }),
      );
      await advance(0);
      expect(result.current.remainingMs).toBe(10_000 - VISIBLE_SLACK_MS);
    });
  });

  it("never goes negative once the slackened deadline has passed", async () => {
    await withFakeTimers(async () => {
      const { result } = renderHook(() =>
        useMatchClock({
          serverNow: iso(0),
          deadline: iso(200),
          visibleSlackMs: VISIBLE_SLACK_MS,
          expire: vi.fn(),
          reconcile: vi.fn(),
        }),
      );
      await advance(0);
      expect(result.current.remainingMs).toBe(0);
    });
  });

  it("reports no remaining time while nothing is timed", async () => {
    await withFakeTimers(async () => {
      const { result } = renderHook(() =>
        useMatchClock({ serverNow: iso(0), deadline: null, expire: vi.fn(), reconcile: vi.fn() }),
      );
      await advance(0);
      expect(result.current.remainingMs).toBeNull();
    });
  });
});

describe("expiry", () => {
  it("waits out the jitter window before the first attempt, rather than firing right at the deadline", async () => {
    await withFakeTimers(async () => {
      const expire = vi.fn();
      renderHook(() =>
        useMatchClock({ serverNow: iso(0), deadline: iso(0), expire, reconcile: vi.fn() }),
      );

      await advance(200, 50);
      expect(expire).not.toHaveBeenCalled();

      await advance(700, 50);
      expect(expire).toHaveBeenCalled();
    });
  });

  it("keeps asking every retry interval rather than firing once and latching after a no-op", async () => {
    await withFakeTimers(async () => {
      // A no-op expiry: the deadline never moves, mirroring a server that
      // disagreed and left the match exactly as it was.
      const expire = vi.fn();
      renderHook(() =>
        useMatchClock({ serverNow: iso(0), deadline: iso(-200), expire, reconcile: vi.fn() }),
      );

      await advance(4_000);
      expect(expire.mock.calls.length).toBeGreaterThan(1);
    });
  });

  it("applies jitter for a non-acting client rather than firing every client at once", async () => {
    await withFakeTimers(async () => {
      const attempts: number[] = [];
      const expire = vi.fn(() => attempts.push(Date.now()));
      renderHook(() =>
        useMatchClock({ serverNow: iso(0), deadline: iso(0), expire, reconcile: vi.fn() }),
      );

      await advance(1_200, 50);
      expect(attempts[0]).toBeGreaterThanOrEqual(NOW + 300);
      expect(attempts[0]).toBeLessThanOrEqual(NOW + 900);
    });
  });

  it("never fires for a client the caller has exempted", async () => {
    await withFakeTimers(async () => {
      const expire = vi.fn();
      renderHook(() =>
        useMatchClock({
          serverNow: iso(0),
          deadline: iso(-2_000),
          skipExpiry: true,
          expire,
          reconcile: vi.fn(),
        }),
      );

      await advance(4_000);
      expect(expire).not.toHaveBeenCalled();
    });
  });

  it("resets its retry cooldown when a fresh deadline replaces the old one", async () => {
    // A fixed jitter (always the minimum, 300ms) makes the fire times exact
    // rather than a range, which is what this test needs to tell "reset" from
    // "carried the old cooldown over" apart.
    const random = vi.spyOn(Math, "random").mockReturnValue(0);
    try {
      await withFakeTimers(async () => {
        const expire = vi.fn();
        const { rerender } = renderHook(
          ({ deadline }: { deadline: string }) =>
            useMatchClock({ serverNow: iso(0), deadline, expire, reconcile: vi.fn() }),
          { initialProps: { deadline: iso(200) } },
        );

        // Fires once, 300ms of jitter after its own 200ms-out deadline.
        await advance(400, 50);
        expect(expire).toHaveBeenCalledTimes(0);
        await advance(200, 50);
        expect(expire).toHaveBeenCalledTimes(1);

        // A later deadline, 900ms out from the same start -- 600ms from here.
        // If the cooldown had carried over instead of resetting, RETRY_MS
        // would still be running out from the first attempt at (roughly) the
        // same moment this one is due, and the assertions below would not
        // tell the two apart. Pushing the second deadline well past that
        // makes a carried-over cooldown and a reset one fire at different
        // times, which is the thing being tested.
        rerender({ deadline: iso(900) });
        await advance(500, 50);
        expect(expire).toHaveBeenCalledTimes(1);
        await advance(200, 50);
        expect(expire).toHaveBeenCalledTimes(2);
      });
    } finally {
      random.mockRestore();
    }
  });
});

/**
 * The fourth behaviour, and the only optional one. A game whose server learns
 * something from being asked — Higher or Lower stamps presence on the same RPC
 * — needs the question put on a cadence, not only once a deadline is past. A
 * game that learns nothing must not pay for it, which is why this is off unless
 * a caller asks.
 */
describe("the heartbeat", () => {
  it("asks nothing at all before the deadline when no caller wants a heartbeat", async () => {
    await withFakeTimers(async () => {
      const expire = vi.fn();
      renderHook(() =>
        useMatchClock({ serverNow: iso(0), deadline: iso(30_000), expire, reconcile: vi.fn() }),
      );

      await advance(12_000);
      expect(expire).not.toHaveBeenCalled();
    });
  });

  it("keeps asking on its own cadence while the deadline is still ahead", async () => {
    await withFakeTimers(async () => {
      const expire = vi.fn();
      renderHook(() =>
        useMatchClock({
          serverNow: iso(0),
          deadline: iso(30_000),
          heartbeatMs: HEARTBEAT_MS,
          expire,
          reconcile: vi.fn(),
        }),
      );

      // A whole call phase is twelve seconds. Presence is judged over one of
      // them, so what matters is that several beats land inside one.
      await advance(12_000);
      expect(expire.mock.calls.length).toBeGreaterThanOrEqual(3);
    });
  });

  it("speaks up as soon as a new phase begins rather than waiting out a beat", async () => {
    await withFakeTimers(async () => {
      const expire = vi.fn();
      const { rerender } = renderHook(
        ({ deadline }: { deadline: string }) =>
          useMatchClock({
            serverNow: iso(0),
            deadline,
            heartbeatMs: HEARTBEAT_MS,
            expire,
            reconcile: vi.fn(),
          }),
        { initialProps: { deadline: iso(30_000) } },
      );

      await advance(500, 100);
      const onArrival = expire.mock.calls.length;
      rerender({ deadline: iso(60_000) });
      await advance(500, 100);

      expect(expire.mock.calls.length).toBeGreaterThan(onArrival);
    });
  });

  it("still switches to the faster retry cadence once the deadline has passed", async () => {
    await withFakeTimers(async () => {
      const beats: number[] = [];
      const expire = vi.fn(() => beats.push(Date.now()));
      renderHook(() =>
        useMatchClock({
          serverNow: iso(0),
          deadline: iso(-200),
          heartbeatMs: HEARTBEAT_MS,
          expire,
          reconcile: vi.fn(),
        }),
      );

      await advance(4_000, 100);
      // Four seconds at the retry cadence is several attempts; four seconds at
      // the heartbeat cadence would be one.
      expect(beats.length).toBeGreaterThan(2);
    });
  });

  it("goes quiet once nothing is timed, so a finished match stops being polled", async () => {
    await withFakeTimers(async () => {
      const expire = vi.fn();
      renderHook(() =>
        useMatchClock({
          serverNow: iso(0),
          deadline: null,
          heartbeatMs: HEARTBEAT_MS,
          expire,
          reconcile: vi.fn(),
        }),
      );

      await advance(12_000);
      expect(expire).not.toHaveBeenCalled();
    });
  });

  it("never asks for a client the caller has exempted, heartbeat or not", async () => {
    await withFakeTimers(async () => {
      const expire = vi.fn();
      renderHook(() =>
        useMatchClock({
          serverNow: iso(0),
          deadline: iso(30_000),
          heartbeatMs: HEARTBEAT_MS,
          skipExpiry: true,
          expire,
          reconcile: vi.fn(),
        }),
      );

      await advance(12_000);
      expect(expire).not.toHaveBeenCalled();
    });
  });
});

describe("reconciliation", () => {
  it("re-reads state once a deadline has stayed past long enough to distrust expiry", async () => {
    await withFakeTimers(async () => {
      const reconcile = vi.fn();
      renderHook(() =>
        useMatchClock({ serverNow: iso(0), deadline: iso(-100), expire: vi.fn(), reconcile }),
      );

      await advance(3_000);
      expect(reconcile).not.toHaveBeenCalled();

      await advance(2_000);
      expect(reconcile).toHaveBeenCalled();
    });
  });

  it("leaves a healthy deadline alone", async () => {
    await withFakeTimers(async () => {
      const reconcile = vi.fn();
      renderHook(() =>
        useMatchClock({ serverNow: iso(0), deadline: iso(20_000), expire: vi.fn(), reconcile }),
      );

      await advance(3_000);
      expect(reconcile).not.toHaveBeenCalled();
    });
  });

  it("re-reads state when the tab returns to the foreground", async () => {
    const reconcile = vi.fn();
    const visible = vi.spyOn(document, "visibilityState", "get").mockReturnValue("visible");
    renderHook(() =>
      useMatchClock({ serverNow: iso(0), deadline: null, expire: vi.fn(), reconcile }),
    );

    act(() => {
      document.dispatchEvent(new Event("visibilitychange"));
    });

    await waitFor(() => expect(reconcile).toHaveBeenCalled());
    visible.mockRestore();
  });

  it("does not reconcile on a visibility change that isn't a return to the foreground", async () => {
    const reconcile = vi.fn();
    const hidden = vi.spyOn(document, "visibilityState", "get").mockReturnValue("hidden");
    renderHook(() =>
      useMatchClock({ serverNow: iso(0), deadline: null, expire: vi.fn(), reconcile }),
    );

    act(() => {
      document.dispatchEvent(new Event("visibilitychange"));
    });

    expect(reconcile).not.toHaveBeenCalled();
    hidden.mockRestore();
  });

  it("exposes the same reconciliation a caller's realtime subscription can drive on channel rejoin", () => {
    const reconcile = vi.fn();
    const { result } = renderHook(() =>
      useMatchClock({ serverNow: iso(0), deadline: null, expire: vi.fn(), reconcile }),
    );

    act(() => result.current.reconcile());

    expect(reconcile).toHaveBeenCalledTimes(1);
  });
});
