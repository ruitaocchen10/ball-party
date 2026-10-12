import type { Outcome, Sender } from "./apns.ts";
import { buildPayload, collapseId, type PushJob } from "./payload.ts";

/** The database side, over the service-role RPCs of migration 0206 and 0205. */
export interface Outbox {
  claim(limit: number): Promise<PushJob[]>;
  finish(id: number, result: "sent" | "retry" | "dead", error?: string): Promise<void>;
  deleteTokens(tokens: string[]): Promise<void>;
}

export interface Summary {
  claimed: number;
  sent: number;
  retried: number;
  dead: number;
  tokensDeleted: number;
}

/**
 * Sends one claimed push to each of the recipient's devices and reports one
 * result for it. A push counts as sent if any device took it. If none did, it is
 * dead when every token was invalid or the failure is permanent, and retried
 * otherwise. Dead tokens are deleted whatever happens to the push.
 */
async function deliver(job: PushJob, send: Sender): Promise<{ result: "sent" | "retry" | "dead"; error?: string; invalid: string[] }> {
  const payload = buildPayload(job);
  const collapse = collapseId(job);
  const results = await Promise.all(
    job.devices.map(async (device) => ({ device, ...(await send(device, payload, collapse)) })),
  );
  const invalid = results.filter((r) => r.outcome === "invalid").map((r) => r.device.token);
  if (results.some((r) => r.outcome === "sent")) return { result: "sent", invalid };

  const failure = results.find((r) => r.outcome === "retry" || r.outcome === "auth");
  if (failure) return { result: "retry", error: failure.detail ?? failure.outcome, invalid };

  const reason: Outcome = results.some((r) => r.outcome === "fatal") ? "fatal" : "invalid";
  const detail = results.find((r) => r.outcome === reason)?.detail;
  return { result: "dead", error: detail ?? reason, invalid };
}

/**
 * Claims and sends until the outbox has nothing due, or `maxBatches` is hit so
 * one invocation stays short; the next tick picks up the rest.
 */
export async function drain(deps: { outbox: Outbox; send: Sender; limit?: number; maxBatches?: number }): Promise<Summary> {
  const limit = deps.limit ?? 50;
  const summary: Summary = { claimed: 0, sent: 0, retried: 0, dead: 0, tokensDeleted: 0 };

  for (let batch = 0; batch < (deps.maxBatches ?? 4); batch++) {
    const jobs = await deps.outbox.claim(limit);
    if (jobs.length === 0) break;
    summary.claimed += jobs.length;

    for (const job of jobs) {
      const done = await deliver(job, deps.send);
      if (done.invalid.length > 0) {
        await deps.outbox.deleteTokens(done.invalid);
        summary.tokensDeleted += done.invalid.length;
      }
      await deps.outbox.finish(job.id, done.result, done.error);
      if (done.result === "sent") summary.sent++;
      else if (done.result === "retry") summary.retried++;
      else summary.dead++;
    }
    if (jobs.length < limit) break;
  }
  return summary;
}
