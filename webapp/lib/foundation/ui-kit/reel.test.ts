import { describe, expect, it, vi } from "vitest";

import { stableReelDecoys } from "@/lib/foundation/ui-kit/reel";

describe("stableReelDecoys", () => {
  it("returns the same decoys for a server and browser render of one reel key", () => {
    const items = ["atl", "buf", "chi", "den", "kan", "phi"];
    const random = vi.spyOn(Math, "random");

    random.mockReturnValueOnce(0.01);
    const serverRows = stableReelDecoys(items, "1-phi-2016-false", 4);
    random.mockReturnValueOnce(0.99);
    const browserRows = stableReelDecoys(items, "1-phi-2016-false", 4);
    random.mockRestore();

    expect(browserRows).toEqual(serverRows);
  });
});
