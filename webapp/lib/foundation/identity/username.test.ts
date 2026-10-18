import { describe, expect, it } from "vitest";

import { usernameClaimError, usernameFormatHint } from "./username";

describe("usernameFormatHint", () => {
  it("accepts well-formed names", () => {
    expect(usernameFormatHint("abc")).toBeNull();
    expect(usernameFormatHint("Ball_Knower_99")).toBeNull();
  });

  it("explains short, long and badly shaped names", () => {
    expect(usernameFormatHint("ab")).toMatch(/at least 3/);
    expect(usernameFormatHint("a".repeat(21))).toMatch(/at most 20/);
    expect(usernameFormatHint("bad name")).toMatch(/letters, numbers and underscores/);
  });
});

describe("usernameClaimError", () => {
  it("maps the RPC errors", () => {
    expect(usernameClaimError({ message: "username_taken" })).toBe("That username is taken.");
    expect(usernameClaimError({ message: "username_reserved" })).toMatch(/isn’t available/);
    expect(usernameClaimError({ message: "invalid_username" })).toMatch(/letters/);
    expect(usernameClaimError({ message: "rate_limited" })).toMatch(/too often/);
    expect(usernameClaimError({ message: "boom" })).toMatch(/couldn’t save/);
  });
});
