import { describe, expect, it } from "vitest";

import { guestSessionFinishedHref, shouldResetGuestSession } from "./guest-lifecycle";

describe("shouldResetGuestSession", () => {
  it("starts a guest fresh after the host ends the game session", () => {
    expect(shouldResetGuestSession({ isGuest: true, postGameChoice: "lobby" })).toBe(true);
  });

  it("keeps a guest identity only when the party is continuing into a replay", () => {
    expect(shouldResetGuestSession({ isGuest: true, postGameChoice: "replay" })).toBe(false);
    expect(shouldResetGuestSession({ isGuest: false, postGameChoice: "lobby" })).toBe(false);
  });

  it("routes the reset through a same-origin sign-out endpoint", () => {
    expect(guestSessionFinishedHref("/lobby/BLTZ")).toBe(
      "/auth/guest-session-finished?next=%2Flobby%2FBLTZ",
    );
  });
});
