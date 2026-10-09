import { beforeEach, describe, expect, it, vi } from "vitest";

const calls: string[] = [];
const list = vi.fn();
const remove = vi.fn();
const rpc = vi.fn();
const signOut = vi.fn();
const getClaims = vi.fn();

vi.mock("next/cache", () => ({ revalidatePath: vi.fn() }));
vi.mock("@/lib/supabase/server", () => ({
  createClient: async () => ({
    auth: { getClaims, signOut },
    rpc,
    storage: { from: () => ({ list, remove }) },
  }),
}));

import { deleteAccount, setProfilePrivate } from "./actions";

describe("deleteAccount", () => {
  beforeEach(() => {
    calls.length = 0;
    vi.resetAllMocks();
    getClaims.mockResolvedValue({ data: { claims: { sub: "user-1" } } });
    list.mockImplementation(async () => (calls.push("list"), { data: [{ name: "avatar.png" }], error: null }));
    remove.mockImplementation(async () => (calls.push("remove"), { data: [], error: null }));
    rpc.mockImplementation(async () => (calls.push("rpc"), { error: null }));
    signOut.mockImplementation(async () => (calls.push("signOut"), { error: null }));
  });

  it("removes the avatar files, then anonymizes, then signs out everywhere", async () => {
    await deleteAccount();

    expect(list).toHaveBeenCalledWith("user-1");
    expect(remove).toHaveBeenCalledWith(["user-1/avatar.png"]);
    expect(rpc).toHaveBeenCalledWith("delete_own_account");
    expect(signOut).toHaveBeenCalledWith({ scope: "global" });
    expect(calls).toEqual(["list", "remove", "rpc", "signOut"]);
  });

  it("skips removal when the player never uploaded an avatar", async () => {
    list.mockResolvedValue({ data: [], error: null });

    await deleteAccount();

    expect(remove).not.toHaveBeenCalled();
    expect(rpc).toHaveBeenCalled();
  });

  it("leaves the account untouched when the avatar files can't be removed", async () => {
    remove.mockResolvedValue({ data: null, error: new Error("storage down") });

    await expect(deleteAccount()).rejects.toThrow("storage down");

    expect(rpc).not.toHaveBeenCalled();
    expect(signOut).not.toHaveBeenCalled();
  });

  it("does not sign out when the RPC fails", async () => {
    rpc.mockResolvedValue({ error: new Error("rpc failed") });

    await expect(deleteAccount()).rejects.toThrow("rpc failed");

    expect(signOut).not.toHaveBeenCalled();
  });

  it("refuses to run signed out", async () => {
    getClaims.mockResolvedValue({ data: { claims: null } });

    await expect(deleteAccount()).rejects.toThrow("not_authenticated");

    expect(list).not.toHaveBeenCalled();
    expect(rpc).not.toHaveBeenCalled();
  });
});

describe("setProfilePrivate", () => {
  beforeEach(() => {
    vi.resetAllMocks();
    getClaims.mockResolvedValue({ data: { claims: { sub: "user-1" } } });
    rpc.mockResolvedValue({ data: true, error: null });
  });

  it("calls the set_profile_private RPC", async () => {
    await expect(setProfilePrivate(true)).resolves.toEqual({ error: null });
    expect(rpc).toHaveBeenCalledWith("set_profile_private", { p_private: true });
  });

  it("reports a failed save", async () => {
    rpc.mockResolvedValue({ data: null, error: { message: "boom" } });
    await expect(setProfilePrivate(false)).resolves.toEqual({ error: "We couldn’t save that. Please try again." });
  });

  it("refuses guests and signed-out visitors without calling the RPC", async () => {
    getClaims.mockResolvedValue({ data: { claims: { sub: "guest-1", is_anonymous: true } } });
    expect(await setProfilePrivate(true)).toEqual({ error: "Create an account to change this." });
    getClaims.mockResolvedValue({ data: { claims: null } });
    expect(await setProfilePrivate(true)).toEqual({ error: "Create an account to change this." });
    expect(rpc).not.toHaveBeenCalled();
  });
});
