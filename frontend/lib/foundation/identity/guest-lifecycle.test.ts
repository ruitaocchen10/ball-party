import { describe, expect, it } from "vitest";

import { guestSessionFinishedHref } from "./guest-lifecycle";

describe("guestSessionFinishedHref", () => {
  it("routes the reset through a same-origin sign-out endpoint", () => {
    expect(guestSessionFinishedHref("/lobby/BLTZ")).toBe(
      "/auth/guest-session-finished?next=%2Flobby%2FBLTZ",
    );
  });
});
