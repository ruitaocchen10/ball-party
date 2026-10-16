// Emails the admins a digest of prompt slots that need attention (BPP-15,
// migration 0215).
//
// Woken once a day by pg_cron through pg_net (prompts_private.schedule_digest_tick),
// which sends the shared secret in `x-digest-secret`. JWT verification is off
// for this function (supabase/config.toml) because the caller is the database.
// It asks public.claim_schedule_digest for the recipients and the items, and
// sends nothing when there are none, so a quiet day produces no email.
//
// Secrets: DIGEST_FUNCTION_SECRET, RESEND_API_KEY, DIGEST_FROM (a sender on a
// domain verified in Resend, e.g. "Ball Party <admin@mail.example.com>"), and
// optionally ADMIN_URL (the calendar's address, linked from the email).
// SUPABASE_URL and SUPABASE_SERVICE_ROLE_KEY are provided by the platform.

import { renderDigest, type DigestItem } from "./digest.ts";

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

async function claimDigest(): Promise<{ recipients: string[]; items: DigestItem[] } | null> {
  const key = required("SUPABASE_SERVICE_ROLE_KEY");
  const response = await fetch(`${required("SUPABASE_URL")}/rest/v1/rpc/claim_schedule_digest`, {
    method: "POST",
    headers: { apikey: key, authorization: `Bearer ${key}`, "content-type": "application/json" },
    body: "{}",
  });
  if (!response.ok) throw new Error(`claim_schedule_digest failed: ${response.status} ${await response.text()}`);
  return (await response.json().catch(() => null)) as { recipients: string[]; items: DigestItem[] } | null;
}

Deno.serve(async (request) => {
  try {
    if (!sameSecret(request.headers.get("x-digest-secret") ?? "", required("DIGEST_FUNCTION_SECRET"))) {
      return new Response("unauthorized", { status: 401 });
    }
    const digest = await claimDigest();
    if (!digest || digest.items.length === 0 || digest.recipients.length === 0) {
      return Response.json({ sent: false });
    }
    const { subject, text } = renderDigest(digest.items, Deno.env.get("ADMIN_URL"));
    const response = await fetch("https://api.resend.com/emails", {
      method: "POST",
      headers: { authorization: `Bearer ${required("RESEND_API_KEY")}`, "content-type": "application/json" },
      body: JSON.stringify({ from: required("DIGEST_FROM"), to: digest.recipients, subject, text }),
    });
    if (!response.ok) throw new Error(`resend failed: ${response.status} ${await response.text()}`);
    return Response.json({ sent: true, items: digest.items.length });
  } catch (error) {
    // Unconfigured, or the database or Resend is unreachable. Nothing was
    // recorded as sent, so tomorrow's tick simply tries again.
    console.error(error);
    return new Response("error", { status: 503 });
  }
});
