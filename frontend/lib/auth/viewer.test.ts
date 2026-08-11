import { describe, expect, it } from "vitest";

import { canCreateLobby, isSignedInViewer } from "./viewer";

describe("isSignedInViewer", () => {
  it("accepts both anonymous and credentialed claims", () => {
    expect(isSignedInViewer({ sub: "guest", is_anonymous: true })).toBe(true);
    expect(isSignedInViewer({ sub: "member", is_anonymous: false })).toBe(true);
  });

  it("rejects absent claims", () => {
    expect(isSignedInViewer(undefined)).toBe(false);
  });

  it("only lets credentialed viewers create a lobby", () => {
    expect(canCreateLobby(undefined)).toBe(false);
    expect(canCreateLobby({ sub: "guest", is_anonymous: true })).toBe(false);
    expect(canCreateLobby({ sub: "member", is_anonymous: false })).toBe(true);
  });
});
