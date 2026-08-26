"use client";

import { useCallback, useState } from "react";

import { AnimatedMessage } from "@/components/motion/AnimatedMessage";
import { Button } from "@/components/ui/Button";
import { createClient } from "@/lib/supabase/client";

const MESSAGE: Record<string, string> = {
  not_host: "Only the host can pause the game.",
  match_not_playing: "The match isn't running right now.",
  match_not_paused: "The match isn't paused.",
  no_host: "Solo matches can't be paused.",
};

/**
 * Host-only pause/resume toggle. Rendered top-right of every game screen.
 *
 * Purely a trigger — whether the match is currently paused is owned by the
 * caller (driven off the match's own realtime status), not by this
 * component, so a second host tab, or a resume the janitor forces, shows up
 * here immediately rather than only after this button's own click resolves.
 */
export function PauseButton({ matchId, paused }: { matchId: string; paused: boolean }) {
  const [pending, setPending] = useState(false);
  const [error, setError] = useState<string | null>(null);

  const toggle = useCallback(async () => {
    setPending(true);
    setError(null);
    const { error: rpcError } = await createClient().rpc(
      paused ? "resume_match" : "pause_match",
      { p_match_id: matchId },
    );
    setPending(false);
    if (rpcError) setError(MESSAGE[rpcError.message] ?? rpcError.message);
  }, [matchId, paused]);

  return (
    <div className="flex flex-col items-end gap-1">
      <Button
        type="button"
        variant="ghost"
        fullWidth={false}
        disabled={pending}
        onClick={() => void toggle()}
      >
        {paused ? "Resume" : "Pause"}
      </Button>
      <AnimatedMessage role="alert" className="text-right font-mono text-[10px] tracking-[0.13em] text-hidden-text uppercase">
        {error}
      </AnimatedMessage>
    </div>
  );
}
