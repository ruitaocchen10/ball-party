import { describe, expect, it } from "vitest";

import { canCreateLobby, canViewProfile, chromeIdentity, isSignedInViewer } from "./viewer";

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

  it("keeps a returning guest out of the durable profile", () => {
    expect(canViewProfile({ sub: "guest", is_anonymous: true })).toBe(false);
    expect(canViewProfile({ sub: "member", is_anonymous: false })).toBe(true);
  });
});

describe("chromeIdentity", () => {
  const profile = { display_name: "Ava", avatar_url: "https://example.test/ava.png" };
  const signedOut = { displayName: null, email: null, avatarUrl: null };

  it("shows an account by its profile", () => {
    expect(chromeIdentity({ sub: "u", is_anonymous: false, email: "ava@example.com" }, profile)).toEqual({
      displayName: "Ava",
      email: "ava@example.com",
      avatarUrl: "https://example.test/ava.png",
    });
  });

  it("falls back to the account's email when its profile has no name", () => {
    expect(chromeIdentity({ sub: "u", email: "ava@example.com" }, { display_name: null, avatar_url: null })).toEqual({
      displayName: "ava@example.com",
      email: "ava@example.com",
      avatarUrl: null,
    });
  });

  it("shows a guest as signed out, whatever its placeholder profile says", () => {
    expect(chromeIdentity({ sub: "g", is_anonymous: true }, { display_name: "Player", avatar_url: null })).toEqual(signedOut);
  });

  it("shows no session as signed out", () => {
    expect(chromeIdentity(null, null)).toEqual(signedOut);
    expect(chromeIdentity(undefined, profile)).toEqual(signedOut);
  });
});
