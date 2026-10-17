// The send-push Edge Function (supabase/functions/send-push) runs on Deno, but
// everything except index.ts is plain TypeScript on web-standard APIs, so it is
// tested here with the rest of the suite. Which pushes exist, coalescing and
// suppression are decided in the database and covered by pgTAP (0206).
import { webcrypto } from "node:crypto";
import { beforeAll, describe, expect, it, vi } from "vitest";

import { classify, createSender, hostFor, signProviderToken } from "../../../supabase/functions/send-push/apns.ts";
import { drain, type Outbox } from "../../../supabase/functions/send-push/drain.ts";
import { buildAlert, buildPayload, clip, collapseId, type PushJob } from "../../../supabase/functions/send-push/payload.ts";

const job = (overrides: Partial<PushJob> = {}): PushJob => ({
  id: 1,
  kind: "friend_request",
  item_key: "n:abc",
  post_id: null,
  badge: 3,
  devices: [{ token: "t1", environment: "sandbox" }],
  ...overrides,
});

describe("payload", () => {
  it("carries the kind and ids, and the badge", () => {
    expect(buildPayload(job())).toMatchObject({ kind: "friend_request", item_key: "n:abc", aps: { badge: 3, sound: "default" } });
  });

  it("falls back to fixed copy without facts, with nothing private in it", () => {
    for (const kind of ["friend_request", "take_reply", "room_invite", "new_prompt"] as const) {
      const { aps } = buildPayload(job({ kind })) as { aps: { alert: { title: string; body: string } } };
      expect(`${aps.alert.title} ${aps.alert.body}`).not.toMatch(/@|:|[0-9a-f]{8}-/);
    }
  });

  it("omits keys that do not apply", () => {
    const payload = buildPayload(job({ kind: "new_prompt", item_key: null, post_id: "p1" }));
    expect(payload).toMatchObject({ kind: "new_prompt", post_id: "p1" });
    expect(payload).not.toHaveProperty("item_key");
  });

  it("collapses on the inbox item, or the prompt", () => {
    expect(collapseId(job())).toBe("n:abc");
    expect(collapseId(job({ kind: "new_prompt", item_key: null, post_id: "p1" }))).toBe("prompt:p1");
  });
});

describe("alert copy", () => {
  const prompt = (info: NonNullable<PushJob["info"]>) => buildAlert(job({ kind: "new_prompt", item_key: null, post_id: "p1", info }));

  it("names the person on friend, reply and invite alerts", () => {
    expect(buildAlert(job({ info: { actor_name: "Sam" } }))).toEqual({ title: "New friend request", body: "Sam wants to be friends." });
    expect(buildAlert(job({ kind: "room_invite", info: { actor_name: "Sam" } })).body).toBe("Sam invited you to a room.");
    expect(buildAlert(job({ kind: "take_reply", info: { actor_name: "Sam", reply_count: 1 } })).body).toBe("Sam replied to your take.");
  });

  it("folds several replies into one alert", () => {
    expect(buildAlert(job({ kind: "take_reply", info: { actor_name: "Sam", reply_count: 3 } }))).toEqual({
      title: "New replies to your take",
      body: "3 new replies, the latest from Sam.",
    });
  });

  it("caps a long name so the sentence survives", () => {
    const { body } = buildAlert(job({ info: { actor_name: "a".repeat(40) } }));
    expect(body).toBe(`${"a".repeat(14)}\u2026 wants to be friends.`);
  });

  it("titles a game pick with the matchup and puts the time and points in the body", () => {
    expect(
      prompt({ template_kind: "game_pick", away_team: "KC", home_team: "BUF", kickoff: "2026-11-01T01:20:00Z", points: 10 }),
    ).toEqual({ title: "KC @ BUF", body: "Pick the winner before kickoff (Sat 9:20 PM ET). 10 pts." });
  });

  it("keeps the longest matchup title short enough for a lock screen", () => {
    const { title } = prompt({ template_kind: "game_pick", away_team: "JAX", home_team: "PHI" });
    expect(title.length).toBeLessThanOrEqual(20);
  });

  it("names the week and the lock time on the weekly kinds", () => {
    const lock_at = "2026-11-04T17:00:00Z";
    expect(prompt({ template_kind: "weekly_picks", week: 9, lock_at })).toEqual({
      title: "Week 9 picks are open",
      body: "Lock in your picks before Wed 12:00 PM ET.",
    });
    expect(prompt({ template_kind: "weekly_awards", week: 8, lock_at }).title).toBe("Week 8 awards");
    expect(prompt({ template_kind: "power_rankings", week: 9, lock_at }).title).toBe("Week 9 power rankings");
    expect(prompt({ template_kind: "bold_predictions", lock_at }).title).toBe("Bold Predictions are open");
  });

  it("uses the caption for a kind with no template, clipped", () => {
    expect(prompt({ template_kind: "custom_multi", caption: "x".repeat(200) }).body).toHaveLength(90);
    expect(prompt({ template_kind: "custom_multi" })).toEqual({ title: "New prompt", body: "A new prompt just dropped." });
  });

  it("clips on whitespace-normalised text", () => {
    expect(clip("  a   b  ", 10)).toBe("a b");
  });

  it("keeps every title within a lock-screen line", () => {
    const infos = [
      { template_kind: "weekly_picks", week: 18, lock_at: "2026-11-04T17:00:00Z" },
      { template_kind: "weekly_awards", week: 18 },
      { template_kind: "power_rankings", week: 18 },
      { template_kind: "bold_predictions" },
    ];
    for (const info of infos) expect(prompt(info).title.length).toBeLessThanOrEqual(35);
  });
});

describe("classify", () => {
  it.each([
    [200, undefined, "sent"],
    [410, "Unregistered", "invalid"],
    [400, "BadDeviceToken", "invalid"],
    [400, "DeviceTokenNotForTopic", "invalid"],
    [403, "ExpiredProviderToken", "auth"],
    [403, "InvalidProviderToken", "retry"],
    [429, "TooManyRequests", "retry"],
    [503, "ServiceUnavailable", "retry"],
    [400, "PayloadTooLarge", "fatal"],
  ] as const)("%s %s is %s", (status, reason, expected) => {
    expect(classify(status, reason)).toBe(expected);
  });
});

describe("provider token", () => {
  let pem: string;
  let publicKey: CryptoKey;

  beforeAll(async () => {
    const pair = await webcrypto.subtle.generateKey({ name: "ECDSA", namedCurve: "P-256" }, true, ["sign", "verify"]);
    const der = new Uint8Array(await webcrypto.subtle.exportKey("pkcs8", pair.privateKey));
    pem = `-----BEGIN PRIVATE KEY-----\n${Buffer.from(der).toString("base64")}\n-----END PRIVATE KEY-----\n`;
    publicKey = pair.publicKey;
  });

  it("is an ES256 JWT with the key id and team, signed by the key", async () => {
    const jwt = await signProviderToken({ keyP8: pem, keyId: "KEY1234567", teamId: "TEAM123456", nowSec: 1_800_000_000 });
    const [header, claims, signature] = jwt.split(".");
    const decode = (part: string) => JSON.parse(Buffer.from(part, "base64url").toString());
    expect(decode(header)).toEqual({ alg: "ES256", kid: "KEY1234567" });
    expect(decode(claims)).toEqual({ iss: "TEAM123456", iat: 1_800_000_000 });
    const valid = await webcrypto.subtle.verify(
      { name: "ECDSA", hash: "SHA-256" },
      publicKey,
      Buffer.from(signature, "base64url"),
      new TextEncoder().encode(`${header}.${claims}`),
    );
    expect(valid).toBe(true);
  });

  it("accepts a key whose newlines were stored as \\n", async () => {
    const flat = pem.trim().replace(/\n/g, "\\n");
    await expect(signProviderToken({ keyP8: flat, keyId: "K", teamId: "T", nowSec: 1 })).resolves.toMatch(/^[\w-]+\.[\w-]+\.[\w-]+$/);
  });
});

describe("sender", () => {
  let pem: string;
  beforeAll(async () => {
    const pair = await webcrypto.subtle.generateKey({ name: "ECDSA", namedCurve: "P-256" }, true, ["sign", "verify"]);
    const der = new Uint8Array(await webcrypto.subtle.exportKey("pkcs8", pair.privateKey));
    pem = `-----BEGIN PRIVATE KEY-----\n${Buffer.from(der).toString("base64")}\n-----END PRIVATE KEY-----`;
  });

  const config = () => ({ keyP8: pem, keyId: "K", teamId: "T", topic: "com.ballparty.app" });
  const reply = (status: number, reason?: string) => new Response(reason ? JSON.stringify({ reason }) : "{}", { status });

  it("routes each token to the host for its environment", async () => {
    const fetchMock = vi.fn(async () => reply(200));
    const send = createSender(config(), { fetch: fetchMock as unknown as typeof fetch });
    await send({ token: "abc", environment: "sandbox" }, { a: 1 }, null);
    await send({ token: "def", environment: "production" }, { a: 1 }, null);
    const urls = fetchMock.mock.calls.map((call) => (call as unknown as [string])[0]);
    expect(urls).toEqual([`${hostFor("sandbox")}/3/device/abc`, `${hostFor("production")}/3/device/def`]);
    expect(hostFor("sandbox")).toContain("sandbox");
    expect(hostFor("production")).not.toContain("sandbox");
  });

  it("sends the topic, alert type and collapse id", async () => {
    const fetchMock = vi.fn(async () => reply(200));
    const send = createSender(config(), { fetch: fetchMock as unknown as typeof fetch });
    await send({ token: "abc", environment: "sandbox" }, { a: 1 }, "n:abc");
    const init = (fetchMock.mock.calls[0] as unknown as [string, RequestInit])[1];
    expect(init.headers).toMatchObject({ "apns-topic": "com.ballparty.app", "apns-push-type": "alert", "apns-collapse-id": "n:abc" });
  });

  it("reuses the provider token, and signs a new one after it expires", async () => {
    let clock = 1_800_000_000_000;
    const fetchMock = vi.fn(async () => reply(200));
    const send = createSender(config(), { fetch: fetchMock as unknown as typeof fetch, now: () => clock });
    const auth = () => fetchMock.mock.calls.map((c) => ((c as unknown as [string, RequestInit])[1].headers as Record<string, string>).authorization);
    await send({ token: "a", environment: "sandbox" }, {}, null);
    await send({ token: "b", environment: "sandbox" }, {}, null);
    expect(auth()[0]).toBe(auth()[1]);
    clock += 55 * 60 * 1000;
    await send({ token: "c", environment: "sandbox" }, {}, null);
    expect(auth()[2]).not.toBe(auth()[0]);
  });

  it("retries once with a fresh token when APNs says it expired", async () => {
    const fetchMock = vi.fn().mockResolvedValueOnce(reply(403, "ExpiredProviderToken")).mockResolvedValueOnce(reply(200));
    const send = createSender(config(), { fetch: fetchMock as unknown as typeof fetch });
    expect((await send({ token: "a", environment: "sandbox" }, {}, null)).outcome).toBe("sent");
    expect(fetchMock).toHaveBeenCalledTimes(2);
  });

  it("treats a network failure as retryable", async () => {
    const send = createSender(config(), { fetch: (async () => { throw new Error("socket closed"); }) as unknown as typeof fetch });
    expect(await send({ token: "a", environment: "sandbox" }, {}, null)).toEqual({ outcome: "retry", detail: "socket closed" });
  });
});

describe("drain", () => {
  function fakeOutbox(batches: PushJob[][]) {
    const finished: Array<[number, string, string | undefined]> = [];
    const deleted: string[][] = [];
    const queue = [...batches];
    const outbox: Outbox = {
      claim: async () => queue.shift() ?? [],
      finish: async (id, result, error) => { finished.push([id, result, error]); },
      deleteTokens: async (tokens) => { deleted.push(tokens); },
    };
    return { outbox, finished, deleted };
  }

  const twoDevices = job({ devices: [{ token: "good", environment: "sandbox" }, { token: "dead", environment: "production" }] });

  it("marks a push sent when any device takes it, and deletes the dead token", async () => {
    const { outbox, finished, deleted } = fakeOutbox([[twoDevices]]);
    const send = vi.fn(async (device: { token: string }) => ({ outcome: device.token === "dead" ? ("invalid" as const) : ("sent" as const) }));
    const summary = await drain({ outbox, send });
    expect(finished).toEqual([[1, "sent", undefined]]);
    expect(deleted).toEqual([["dead"]]);
    expect(summary).toMatchObject({ claimed: 1, sent: 1, tokensDeleted: 1 });
  });

  it("kills a push whose every token is invalid, and cleans them up", async () => {
    const { outbox, finished, deleted } = fakeOutbox([[twoDevices]]);
    await drain({ outbox, send: async () => ({ outcome: "invalid" }) });
    expect(finished[0][1]).toBe("dead");
    expect(deleted).toEqual([["good", "dead"]]);
  });

  it("retries on an APNs failure and keeps the tokens", async () => {
    const { outbox, finished, deleted } = fakeOutbox([[job()]]);
    await drain({ outbox, send: async () => ({ outcome: "retry", detail: "503 ServiceUnavailable" }) });
    expect(finished).toEqual([[1, "retry", "503 ServiceUnavailable"]]);
    expect(deleted).toEqual([]);
  });

  it("gives up on a payload APNs will never accept", async () => {
    const { outbox, finished } = fakeOutbox([[job()]]);
    await drain({ outbox, send: async () => ({ outcome: "fatal", detail: "400 PayloadTooLarge" }) });
    expect(finished).toEqual([[1, "dead", "400 PayloadTooLarge"]]);
  });

  it("sends every push in a batch and keeps going while batches are full", async () => {
    const { outbox, finished } = fakeOutbox([[job({ id: 1 }), job({ id: 2 })], [job({ id: 3 })]]);
    const summary = await drain({ outbox, send: async () => ({ outcome: "sent" }), limit: 2 });
    expect(finished.map((f) => f[0])).toEqual([1, 2, 3]);
    expect(summary.sent).toBe(3);
  });

  it("stops after maxBatches so one run stays short", async () => {
    const full = () => [job({ id: 1 })];
    const { outbox } = fakeOutbox([full(), full(), full(), full(), full()]);
    const summary = await drain({ outbox, send: async () => ({ outcome: "sent" }), limit: 1, maxBatches: 2 });
    expect(summary.claimed).toBe(2);
  });

  it("does nothing when nothing is due", async () => {
    const { outbox, finished } = fakeOutbox([]);
    const send = vi.fn();
    expect(await drain({ outbox, send })).toMatchObject({ claimed: 0 });
    expect(send).not.toHaveBeenCalled();
    expect(finished).toEqual([]);
  });
});
