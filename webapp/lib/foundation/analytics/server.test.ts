import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";

const captureImmediate = vi.fn().mockResolvedValue(undefined);
const shutdown = vi.fn().mockResolvedValue(undefined);
const cookieHeader = vi.fn<() => string>();

vi.mock("posthog-node", () => ({
  PostHog: class {
    captureImmediate = captureImmediate;
    _shutdown = shutdown;
  },
}));
vi.mock("next/headers", () => ({
  cookies: async () => ({ toString: cookieHeader }),
}));
// Runs the scheduled work straight away so the test can await it.
const scheduled: (() => Promise<void>)[] = [];
vi.mock("next/server", () => ({ after: (work: () => Promise<void>) => scheduled.push(work) }));

import { trackServer } from "@/lib/foundation/analytics/server";

async function flush() {
  await Promise.all(scheduled.splice(0).map((work) => work()));
}

describe("trackServer", () => {
  beforeEach(() => {
    cookieHeader.mockReturnValue("");
    vi.stubEnv("NEXT_PUBLIC_POSTHOG_KEY", "phc_test");
  });
  afterEach(() => {
    vi.unstubAllEnvs();
    scheduled.length = 0;
  });

  it("sends the event for the user after the response", async () => {
    await trackServer("user-1", "party_created", {});
    expect(captureImmediate).not.toHaveBeenCalled();

    await flush();
    expect(captureImmediate).toHaveBeenCalledWith(
      expect.objectContaining({
        distinctId: "user-1",
        event: "party_created",
        properties: expect.objectContaining({ platform: "web", $geoip_disable: true }),
      }),
    );
    expect(shutdown).toHaveBeenCalled();
  });

  it("sends nothing for a browser that opted out", async () => {
    cookieHeader.mockReturnValue("bp_analytics_optout=1");
    await trackServer("user-1", "party_created", {});
    await flush();
    expect(captureImmediate).not.toHaveBeenCalled();
  });

  it("sends nothing without a project key or a user", async () => {
    vi.stubEnv("NEXT_PUBLIC_POSTHOG_KEY", "");
    await trackServer("user-1", "party_created", {});
    vi.stubEnv("NEXT_PUBLIC_POSTHOG_KEY", "phc_test");
    await trackServer(undefined, "party_created", {});
    await flush();
    expect(captureImmediate).not.toHaveBeenCalled();
  });
});
