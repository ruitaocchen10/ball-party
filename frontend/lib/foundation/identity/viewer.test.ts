import { afterEach, describe, expect, it } from "vitest";

import { canCreateLobby, canViewProfile, isAdminViewer, isSignedInViewer } from "./viewer";

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
