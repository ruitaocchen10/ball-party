"use client";

import { useRouter } from "next/navigation";
import { useState } from "react";

import { Button } from "@/components/foundation/ui-kit/Button";
import { clearScheduleSlot, unreadyScheduleSlot } from "@/lib/foundation/content/prompts/schedule";
import { createClient } from "@/lib/supabase/client";

/**
 * Take a ready slot back to draft, or throw a draft away. The RPCs decide
 * whether that is allowed; this only shows their refusal.
 */
export function QueueActions({ slotId, ready }: { slotId: string; ready: boolean }) {
  const router = useRouter();
  const [pending, setPending] = useState(false);
  const [error, setError] = useState<string | null>(null);

  async function run(action: typeof clearScheduleSlot) {
    setPending(true);
    setError(null);
    const result = await action(createClient(), slotId);
    setPending(false);
    if (result.error) setError(result.error);
    else router.refresh();
  }

  return (
    <div className="flex flex-col items-end gap-1">
      <div className="flex gap-2">
        {ready ? (
          <Button size="sm" variant="ghost" fullWidth={false} disabled={pending} onClick={() => run(unreadyScheduleSlot)}>
            Back to draft
          </Button>
        ) : (
          <Button size="sm" variant="danger" fullWidth={false} disabled={pending} onClick={() => run(clearScheduleSlot)}>
            Discard draft
          </Button>
        )}
      </div>
      {error ? <p role="alert" className="text-sm text-hidden-text">{error}</p> : null}
    </div>
  );
}
