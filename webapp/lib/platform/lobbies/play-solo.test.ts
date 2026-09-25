import { beforeEach, describe, expect, it, vi } from "vitest";

/** What `redirect` does in a server action: it throws, so nothing after it runs. */
class Redirected extends Error {
  constructor(readonly url: string) {
    super(`redirect:${url}`);
  }
}

const redirect = vi.fn((url: string) => {
  throw new Redirected(url);
});
vi.mock("next/navigation", () => ({ redirect: (url: string) => redirect(url) }));
vi.mock("next/cache", () => ({ revalidatePath: vi.fn() }));

const client = {
  auth: { getClaims: vi.fn(), signInAnonymously: vi.fn(), signOut: vi.fn() },
  rpc: vi.fn(),
  schema: vi.fn(),
};
vi.mock("@/lib/supabase/server", () => ({ createClient: async () => client }));

import { playSolo } from "./actions";

function form(fields: Record<string, string>): FormData {
  const data = new FormData();
  for (const [key, value] of Object.entries(fields)) data.set(key, value);
  return data;
}

async function destination(action: Promise<void>): Promise<string> {
  try {
    await action;
  } catch (error) {
    if (error instanceof Redirected) return error.url;
    throw error;
  }
  throw new Error("the action did not redirect");
}

const gameRpc = vi.fn();

beforeEach(() => {
  vi.clearAllMocks();
  client.auth.getClaims.mockResolvedValue({ data: { claims: null } });
  client.auth.signInAnonymously.mockResolvedValue({ error: null });
  client.auth.signOut.mockResolvedValue({ error: null });
  client.rpc.mockResolvedValue({ data: { id: "match-1" }, error: null });
  gameRpc.mockResolvedValue({ error: null });
  client.schema.mockReturnValue({ rpc: gameRpc });
});

describe("playSolo — visitors without an account", () => {
  it("starts a guest session for a visitor with none, then deals the run into it", async () => {
    const url = await destination(playSolo(form({ game: "qb_season_builder", mode: "hidden" })));

    expect(client.auth.signInAnonymously).toHaveBeenCalledTimes(1);
    // The session exists before anything that reads auth.uid() runs.
    expect(client.auth.signInAnonymously.mock.invocationCallOrder[0]).toBeLessThan(client.rpc.mock.invocationCallOrder[0]);
    expect(client.rpc).toHaveBeenCalledWith("start_solo_run", { p_game: "qb_season_builder" });
    expect(gameRpc).toHaveBeenCalledWith("start", { p_match_id: "match-1", p_mode: "hidden" });
    expect(url).toBe("/match/match-1");
  });

  it("does not start a second guest for someone who already has a session, a guest included", async () => {
    client.auth.getClaims.mockResolvedValue({ data: { claims: { sub: "user-1", is_anonymous: true } } });

    const url = await destination(playSolo(form({ game: "higher_or_lower" })));

    expect(client.auth.signInAnonymously).not.toHaveBeenCalled();
    expect(url).toBe("/match/match-1");
  });

  it("says so, and starts nothing, when a guest session cannot be created", async () => {
    client.auth.signInAnonymously.mockResolvedValue({ error: { message: "Anonymous sign-ins are disabled" } });

    const url = await destination(playSolo(form({ game: "higher_or_lower" })));

    expect(client.rpc).not.toHaveBeenCalled();
    expect(url).toMatch(/^\/solo\?error=/);
    expect(decodeURIComponent(url)).toMatch(/guest session/i);
  });

  it("refuses a game that is not a solo game before it creates anything", async () => {
    const url = await destination(playSolo(form({ game: "auction_team_builder" })));

    expect(client.auth.signInAnonymously).not.toHaveBeenCalled();
    expect(client.rpc).not.toHaveBeenCalled();
    expect(url).toMatch(/^\/solo\?error=/);
  });
});

describe("playSolo — a session whose user no longer exists", () => {
  const staleSession = { data: { claims: { sub: "deleted-user", is_anonymous: true } } };
  const userGone = { data: null, error: { code: "23503", message: 'violates foreign key constraint "run_participants_user_id_fkey"' } };
  const started = { data: { id: "match-1" }, error: null };

  it("drops the session and starts over as a new guest instead of showing the constraint error", async () => {
    client.auth.getClaims.mockResolvedValue(staleSession);
    client.rpc.mockResolvedValueOnce(userGone).mockResolvedValueOnce(started);

    const url = await destination(playSolo(form({ game: "higher_or_lower" })));

    expect(client.auth.signOut).toHaveBeenCalledWith({ scope: "local" });
    expect(client.auth.signInAnonymously).toHaveBeenCalledTimes(1);
    expect(client.rpc).toHaveBeenCalledTimes(2);
    expect(url).toBe("/match/match-1");
  });

  it("tries again only once, so a real constraint failure cannot loop", async () => {
    client.auth.getClaims.mockResolvedValue(staleSession);
    client.rpc.mockResolvedValue(userGone);

    const url = await destination(playSolo(form({ game: "higher_or_lower" })));

    expect(client.rpc).toHaveBeenCalledTimes(2);
    expect(client.auth.signInAnonymously).toHaveBeenCalledTimes(1);
    expect(url).toMatch(/^\/solo\?error=/);
  });

  it("leaves the session alone for any other failure", async () => {
    client.auth.getClaims.mockResolvedValue(staleSession);
    client.rpc.mockResolvedValue({ data: null, error: { code: "42501", message: "not_authenticated" } });

    const url = await destination(playSolo(form({ game: "higher_or_lower" })));

    expect(client.auth.signOut).not.toHaveBeenCalled();
    expect(client.auth.signInAnonymously).not.toHaveBeenCalled();
    expect(client.rpc).toHaveBeenCalledTimes(1);
    expect(url).toMatch(/^\/solo\?error=/);
  });
});

