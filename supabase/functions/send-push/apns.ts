import type { ApnsEnvironment, Device } from "./payload.ts";

const HOSTS: Record<ApnsEnvironment, string> = {
  sandbox: "https://api.sandbox.push.apple.com",
  production: "https://api.push.apple.com",
};

/** The host a token must be sent to: a debug build's token only works on the sandbox. */
export function hostFor(environment: ApnsEnvironment): string {
  return HOSTS[environment];
}

/**
 * What a send came to.
 *   sent     APNs accepted it.
 *   invalid  the token is dead (410, BadDeviceToken, Unregistered): delete it.
 *   auth     the provider token was rejected as expired: sign a new one and retry.
 *   retry    APNs or the network had a problem: try again later.
 *   fatal    this payload will never be accepted: do not retry.
 */
export type Outcome = "sent" | "invalid" | "auth" | "retry" | "fatal";

export function classify(status: number, reason: string | undefined): Outcome {
  if (status === 200) return "sent";
  if (status === 410) return "invalid";
  if (status === 400 && (reason === "BadDeviceToken" || reason === "DeviceTokenNotForTopic")) return "invalid";
  if (reason === "Unregistered") return "invalid";
  if (status === 403 && reason === "ExpiredProviderToken") return "auth";
  // A bad key or topic is our configuration, not the token's fault; keep the token and keep trying.
  if (status === 403) return "retry";
  if (status === 429 || status >= 500) return "retry";
  return "fatal";
}

const b64url = (bytes: Uint8Array): string =>
  btoa(String.fromCharCode(...bytes)).replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/, "");

const text = (value: unknown): string => b64url(new TextEncoder().encode(JSON.stringify(value)));

function pemToDer(pem: string): ArrayBuffer {
  const body = pem
    .replace(/\\n/g, "\n")
    .replace(/-----BEGIN [A-Z ]+-----/, "")
    .replace(/-----END [A-Z ]+-----/, "")
    .replace(/\s+/g, "");
  const binary = atob(body);
  const der = new Uint8Array(new ArrayBuffer(binary.length));
  for (let i = 0; i < binary.length; i++) der[i] = binary.charCodeAt(i);
  return der.buffer;
}

/** The ES256 JWT APNs wants in `authorization: bearer`. Valid for under an hour. */
export async function signProviderToken(opts: {
  keyP8: string;
  keyId: string;
  teamId: string;
  nowSec: number;
}): Promise<string> {
  const key = await crypto.subtle.importKey(
    "pkcs8",
    pemToDer(opts.keyP8),
    { name: "ECDSA", namedCurve: "P-256" },
    false,
    ["sign"],
  );
  const signingInput = `${text({ alg: "ES256", kid: opts.keyId })}.${text({ iss: opts.teamId, iat: opts.nowSec })}`;
  // WebCrypto returns the raw r||s form JWT uses, not DER.
  const signature = await crypto.subtle.sign(
    { name: "ECDSA", hash: "SHA-256" },
    key,
    new TextEncoder().encode(signingInput),
  );
  return `${signingInput}.${b64url(new Uint8Array(signature))}`;
}

export interface ApnsConfig {
  keyP8: string;
  keyId: string;
  teamId: string;
  /** The app's bundle id, sent as `apns-topic`. */
  topic: string;
}

export type Sender = (
  device: Device,
  payload: Record<string, unknown>,
  collapseId: string | null,
) => Promise<{ outcome: Outcome; detail?: string }>;

// APNs asks that the provider token be reused, and refreshed no more than once
// every 20 minutes and no less than once an hour.
const TOKEN_TTL_SEC = 50 * 60;

export function createSender(
  config: ApnsConfig,
  deps: { fetch?: typeof fetch; now?: () => number } = {},
): Sender {
  const doFetch = deps.fetch ?? fetch;
  const now = deps.now ?? (() => Date.now());
  let cached: { jwt: string; at: number } | null = null;

  async function providerToken(force: boolean): Promise<string> {
    const nowSec = Math.floor(now() / 1000);
    if (!force && cached && nowSec - cached.at < TOKEN_TTL_SEC) return cached.jwt;
    cached = { jwt: await signProviderToken({ ...config, nowSec }), at: nowSec };
    return cached.jwt;
  }

  async function attempt(device: Device, body: string, collapse: string | null, force: boolean) {
    const response = await doFetch(`${hostFor(device.environment)}/3/device/${device.token}`, {
      method: "POST",
      headers: {
        authorization: `bearer ${await providerToken(force)}`,
        "apns-topic": config.topic,
        "apns-push-type": "alert",
        "apns-priority": "10",
        ...(collapse ? { "apns-collapse-id": collapse.slice(0, 64) } : {}),
      },
      body,
    });
    if (response.status === 200) return { outcome: classify(200, undefined) };
    const reason = await response
      .json()
      .then((json: { reason?: string }) => json.reason)
      .catch(() => undefined);
    return { outcome: classify(response.status, reason), detail: `${response.status} ${reason ?? ""}`.trim() };
  }

  return async (device, payload, collapse) => {
    const body = JSON.stringify(payload);
    try {
      const first = await attempt(device, body, collapse, false);
      if (first.outcome !== "auth") return first;
      return await attempt(device, body, collapse, true);
    } catch (error) {
      return { outcome: "retry", detail: error instanceof Error ? error.message : String(error) };
    }
  };
}
