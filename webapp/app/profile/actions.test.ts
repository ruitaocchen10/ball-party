import { beforeEach, describe, expect, it, vi } from "vitest";

const rpc = vi.fn();
const getClaims = vi.fn();
const eq = vi.fn();
const update = vi.fn(() => ({ eq }));

vi.mock("next/cache", () => ({ revalidatePath: vi.fn() }));
vi.mock("@/lib/supabase/server", () => ({
  createClient: async () => ({
    auth: { getClaims },
    rpc,
    from: () => ({ update }),
  }),
}));

import { checkUsernameAvailable, updateProfile } from "./actions";

function form(fields: Record<string, string>) {
  const data = new FormData();
  for (const [key, value] of Object.entries(fields)) data.set(key, value);
  return data;
}

const empty = { error: null, saved: false };

beforeEach(() => {
  vi.resetAllMocks();
  update.mockImplementation(() => ({ eq }));
  getClaims.mockResolvedValue({ data: { claims: { sub: "user-1" } } });
  eq.mockResolvedValue({ error: null });
  rpc.mockResolvedValue({ data: null, error: null });
});

describe("checkUsernameAvailable", () => {
  it("returns the RPC's answer", async () => {
    rpc.mockResolvedValue({ data: false, error: null });
    await expect(checkUsernameAvailable("taken_one")).resolves.toEqual({ available: false, error: null });
    expect(rpc).toHaveBeenCalledWith("username_available", { p_username: "taken_one" });
  });

  it("says to slow down when rate limited", async () => {
    rpc.mockResolvedValue({ data: null, error: { message: "rate_limited" } });
    const result = await checkUsernameAvailable("abc");
    expect(result.available).toBeNull();
    expect(result.error).toMatch(/slow down/i);
  });

  it("does not call the RPC for guests", async () => {
    getClaims.mockResolvedValue({ data: { claims: { sub: "g", is_anonymous: true } } });
    const result = await checkUsernameAvailable("abc");
    expect(result.available).toBeNull();
    expect(rpc).not.toHaveBeenCalled();
  });
});

describe("updateProfile with a username", () => {
  const base = { display_name: "Taylor", avatar_url: "", current_username: "Taylor" };

  it("does not claim when the username is unchanged", async () => {
    const result = await updateProfile(empty, form({ ...base, username: "Taylor" }));
    expect(result).toEqual({ error: null, saved: true });
    expect(rpc).not.toHaveBeenCalled();
    expect(update).toHaveBeenCalledWith({ display_name: "Taylor", avatar_url: null });
  });

  it("claims a changed username before saving the rest", async () => {
    const result = await updateProfile(empty, form({ ...base, username: "Tay_QB" }));
    expect(result).toEqual({ error: null, saved: true });
    expect(rpc).toHaveBeenCalledWith("claim_username", { p_username: "Tay_QB" });
    expect(rpc.mock.invocationCallOrder[0]).toBeLessThan(update.mock.invocationCallOrder[0]);
  });

  it("saves nothing when the username is refused", async () => {
    rpc.mockResolvedValue({ data: null, error: { message: "username_taken" } });
    const result = await updateProfile(empty, form({ ...base, username: "Tay_QB" }));
    expect(result).toEqual({ error: "That username is taken.", saved: false });
    expect(update).not.toHaveBeenCalled();
  });

  it("rejects an obviously malformed username without any server call", async () => {
    const result = await updateProfile(empty, form({ ...base, username: "no spaces" }));
    expect(result.saved).toBe(false);
    expect(result.error).toMatch(/letters, numbers and underscores/);
    expect(rpc).not.toHaveBeenCalled();
    expect(update).not.toHaveBeenCalled();
  });
});
