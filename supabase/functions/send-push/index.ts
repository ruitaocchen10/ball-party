// Sends the push notifications queued in public.push_outbox (migration 0206).
//
// Woken every 15 seconds by pg_cron through pg_net (private.push_drain_tick),
// which sends the shared secret in `x-push-secret`. JWT verification is off for
// this function (supabase/config.toml) because the caller is the database, not
// a signed-in user. It claims due pushes, sends them over HTTP/2 to APNs and
// reports each result back. Nothing here can fail the action that queued a push:
// that finished long before.
//
// Secrets: PUSH_FUNCTION_SECRET, APNS_KEY_P8, APNS_KEY_ID, APNS_TEAM_ID,
// APNS_BUNDLE_ID (scripts/apns/setup.sh). SUPABASE_URL and
// SUPABASE_SERVICE_ROLE_KEY are provided by the platform.

import { createSender } from "./apns.ts";
import { drain, type Outbox } from "./drain.ts";
import type { PushJob } from "./payload.ts";

function required(name: string): string {
  const value = Deno.env.get(name);
  if (!value) throw new Error(`${name} is not set`);
  return value;
}

/** Compares without leaking where the first difference is. */
function sameSecret(a: string, b: string): boolean {
  const x = new TextEncoder().encode(a);
  const y = new TextEncoder().encode(b);
  let diff = x.length ^ y.length;
  for (let i = 0; i < Math.max(x.length, y.length); i++) diff |= (x[i] ?? 0) ^ (y[i] ?? 0);
  return diff === 0;
}

function rpcOutbox(url: string, serviceKey: string): Outbox {
  async function rpc(name: string, args: Record<string, unknown>): Promise<unknown> {
    const response = await fetch(`${url}/rest/v1/rpc/${name}`, {
      method: "POST",
      headers: { apikey: serviceKey, authorization: `Bearer ${serviceKey}`, "content-type": "application/json" },
      body: JSON.stringify(args),
    });
    if (!response.ok) throw new Error(`${name} failed: ${response.status} ${await response.text()}`);
    return response.status === 204 ? null : await response.json().catch(() => null);
  }
  return {
    claim: async (limit) => ((await rpc("claim_push_batch", { p_limit: limit })) as PushJob[] | null) ?? [],
    finish: async (id, result, error) => {
      await rpc("finish_push", { p_id: id, p_result: result, p_error: error ?? null });
    },
    deleteTokens: async (tokens) => {
      await rpc("delete_device_tokens", { p_tokens: tokens });
    },
  };
}

Deno.serve(async (request) => {
  try {
    if (!sameSecret(request.headers.get("x-push-secret") ?? "", required("PUSH_FUNCTION_SECRET"))) {
      return new Response("unauthorized", { status: 401 });
    }
    const send = createSender({
      keyP8: required("APNS_KEY_P8"),
      keyId: required("APNS_KEY_ID"),
      teamId: required("APNS_TEAM_ID"),
      topic: required("APNS_BUNDLE_ID"),
    });
    const outbox = rpcOutbox(required("SUPABASE_URL"), required("SUPABASE_SERVICE_ROLE_KEY"));
    const summary = await drain({ outbox, send });
    return Response.json(summary);
  } catch (error) {
    // Unconfigured or the database is unreachable: nothing was claimed, so the
    // next tick simply tries again.
    console.error(error);
    return new Response("error", { status: 503 });
  }
});
