import { NextRequest } from "next/server";
import { beforeEach, describe, expect, it, vi } from "vitest";

const getClaims = vi.fn();

vi.mock("@supabase/ssr", () => ({
  createServerClient: () => ({ auth: { getClaims } }),
}));

import { updateSession } from "./proxy";

describe("guest route access", () => {
  beforeEach(() => {
    getClaims.mockResolvedValue({ data: { claims: { sub: "guest", is_anonymous: true } } });
  });

  it("keeps Party available when an anonymous session has not restored yet", async () => {
    getClaims.mockResolvedValue({ data: { claims: null } });
    const response = await updateSession(new NextRequest("http://localhost/party"));

    expect(response.headers.get("location")).toBeNull();
  });
});

describe("a QB Season Builder result link", () => {
  const result = "http://localhost/solo/qb-season-builder/result/22222222-2222-2222-2222-222222222222";

  beforeEach(() => {
    getClaims.mockResolvedValue({ data: { claims: null } });
  });

  it("opens for someone who is signed out, so a shared link works for anyone", async () => {
    const response = await updateSession(new NextRequest(result));

    expect(response.headers.get("location")).toBeNull();
  });

  it("is not how a run itself is reached: its own screen still wants a session", async () => {
    const response = await updateSession(
      new NextRequest("http://localhost/match/22222222-2222-2222-2222-222222222222"),
    );

    expect(new URL(response.headers.get("location")!).pathname).toBe("/login");
  });
});
