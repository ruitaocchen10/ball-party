import { afterEach, describe, expect, it } from "vitest";

import { canCreateLobby, canViewProfile, chromeIdentity, isAdminViewer, isSignedInViewer } from "./viewer";

const originalPromptAdmins = process.env.PROMPTS_ADMIN_EMAILS;
const originalAdmin = process.env.ADMIN_EMAIL;

afterEach(() => {
  if (originalPromptAdmins === undefined) delete process.env.PROMPTS_ADMIN_EMAILS;
  else process.env.PROMPTS_ADMIN_EMAILS = originalPromptAdmins;
  if (originalAdmin === undefined) delete process.env.ADMIN_EMAIL;
  else process.env.ADMIN_EMAIL = originalAdmin;
});

describe("isSignedInViewer", () => {
  it("accepts both anonymous and credentialed claims", () => {
    expect(isSignedInViewer({ sub: "guest", is_anonymous: true })).toBe(true);
    expect(isSignedInViewer({ sub: "member", is_anonymous: false })).toBe(true);
  });

  it("accepts any configured prompt composer email", () => {
    process.env.PROMPTS_ADMIN_EMAILS = "first@example.com, Second@example.com";
    expect(isAdminViewer({ email: "second@example.com" })).toBe(true);
    expect(isAdminViewer({ email: "other@example.com" })).toBe(false);
  });

  it("accepts the local demo prompt admin", () => {
    process.env.PROMPTS_ADMIN_EMAILS = "demo@ballparty.local";
    expect(isAdminViewer({ email: "demo@ballparty.local" })).toBe(true);
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
