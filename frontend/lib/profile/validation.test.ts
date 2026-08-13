import { describe, expect, it } from "vitest";

import { validateProfileUpdate } from "@/lib/profile/validation";

describe("validateProfileUpdate", () => {
  it("trims a valid display name and accepts an empty avatar URL", () => {
    expect(validateProfileUpdate("  Kayla  ", "")).toEqual({
      displayName: "Kayla",
      avatarUrl: null,
    });
  });

  it("rejects an invalid display name and avatar URL", () => {
    expect(validateProfileUpdate("K", "not a URL")).toEqual({
      error: "Display name must be 2–16 characters.",
    });
  });

  it("only accepts web avatar URLs", () => {
    expect(validateProfileUpdate("Kayla", "ftp://example.com/avatar.png")).toEqual({
      error: "Avatar URL must start with http:// or https://.",
    });
  });
});
