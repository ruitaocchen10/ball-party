import { beforeEach, describe, expect, it, vi } from "vitest";
import { NextRequest } from "next/server";

const verifyOtp = vi.fn();
const rpc = vi.fn();

vi.mock("@/lib/supabase/server", () => ({
  createClient: async () => ({ auth: { verifyOtp }, rpc }),
}));

import { GET } from "./route";

const link = (type: string) =>
  new NextRequest(`https://ballparty.test/auth/confirm?token_hash=abc&type=${type}&next=/`);

beforeEach(() => {
  verifyOtp.mockReset();
  rpc.mockReset();
  rpc.mockResolvedValue({ data: null, error: null });
});

describe("GET /auth/confirm", () => {
  it("claims the username typed at signup once the email is confirmed", async () => {
    verifyOtp.mockResolvedValue({ data: { user: { user_metadata: { username: "Tay_QB" } } }, error: null });
    const response = await GET(link("signup"));
    expect(rpc).toHaveBeenCalledWith("claim_username", { p_username: "Tay_QB" });
    expect(response.headers.get("location")).toBe("https://ballparty.test/");
  });

  it("still signs the player in when the claim is refused", async () => {
    verifyOtp.mockResolvedValue({ data: { user: { user_metadata: { username: "taken" } } }, error: null });
    rpc.mockResolvedValue({ data: null, error: { message: "username_taken" } });
    const response = await GET(link("signup"));
    expect(response.headers.get("location")).toBe("https://ballparty.test/");
  });

  it("does not claim for other link types or when no username was typed", async () => {
    verifyOtp.mockResolvedValue({ data: { user: { user_metadata: { username: "Tay_QB" } } }, error: null });
    await GET(link("recovery"));
    verifyOtp.mockResolvedValue({ data: { user: { user_metadata: {} } }, error: null });
    await GET(link("signup"));
    expect(rpc).not.toHaveBeenCalled();
  });
});
