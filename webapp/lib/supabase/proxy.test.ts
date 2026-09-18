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
