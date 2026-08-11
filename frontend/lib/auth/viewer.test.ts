import { describe, expect, it } from "vitest";

import { isSignedInViewer } from "./viewer";

describe("isSignedInViewer", () => {
  it("accepts both anonymous and credentialed claims", () => {
    expect(isSignedInViewer({ sub: "guest", is_anonymous: true })).toBe(true);
    expect(isSignedInViewer({ sub: "member", is_anonymous: false })).toBe(true);
  });

  it("rejects absent claims", () => {
    expect(isSignedInViewer(undefined)).toBe(false);
  });
});
