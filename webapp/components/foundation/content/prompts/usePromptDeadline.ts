"use client";

import { useEffect, useState } from "react";

import type { Post } from "@/lib/foundation/content/prompts/types";

/** Re-renders a prompt surface at its deadline without waiting for a refresh. */
export function usePromptDeadlineNow(post: Pick<Post, "status" | "lockAt">): number {
  const [now, setNow] = useState(() => Date.now());
  const closesAt = new Date(post.lockAt).getTime();

  useEffect(() => {
    if (post.status !== "open" || !Number.isFinite(closesAt) || closesAt <= now) return;
    // Browsers cap a single timeout at a signed 32-bit value. Re-schedule at
    // that boundary for unusually distant deadlines instead of overflowing
    // and making the prompt appear closed immediately.
    const timeout = window.setTimeout(() => setNow(Date.now()), Math.min(closesAt - now, 2_147_483_647));
    return () => window.clearTimeout(timeout);
  }, [closesAt, now, post.status]);

  return now;
}
