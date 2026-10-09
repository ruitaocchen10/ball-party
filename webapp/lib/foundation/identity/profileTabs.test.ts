import { describe, expect, it } from "vitest";

import { parseProfileTab } from "./profileTabs";

describe("parseProfileTab", () => {
  it("accepts each tab, first value of an array included", () => {
    expect(parseProfileTab("takes")).toBe("takes");
    expect(parseProfileTab(["friends", "takes"])).toBe("friends");
  });

  it("falls back to stats", () => {
    expect(parseProfileTab("activity")).toBe("stats");
    expect(parseProfileTab(undefined)).toBe("stats");
  });
});
