"use client";

import { useRef, useState } from "react";

import { BallVote } from "@/components/foundation/ui-kit/BallVote";
import { reactToTake } from "@/lib/foundation/content/prompts/reactions";
import type { TakeReaction } from "@/lib/foundation/content/prompts/types";
import { createClient } from "@/lib/supabase/client";

/** The ball control on a take. Updates at once and settles on what the server says; a refusal puts it back. */
export function TakeBallVote({ takeId, initial }: { takeId: string; initial: TakeReaction }) {
  const [state, setState] = useState(initial);
  const [pending, setPending] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const clientRef = useRef<ReturnType<typeof createClient> | null>(null);

  async function react(next: -1 | 1) {
    const value = state.mine === next ? 0 : next;
    const before = state;
    setError(null);
    setPending(true);
    setState({ ...state, mine: value, net: state.net - state.mine + value });
    const result = await reactToTake((clientRef.current ??= createClient()), { takeId, value });
    setPending(false);
    if (result.error !== null) {
      setState(before);
      setError(result.error);
      return;
    }
    setState((current) => ({ ...current, net: result.net, mine: result.mine }));
  }

  return (
    <span className="inline-flex flex-col gap-1">
      <BallVote
        net={state.net}
        mine={state.mine}
        canLike={state.canLike}
        canDislike={state.canDislike}
        pending={pending}
        onLike={() => void react(1)}
        onDislike={() => void react(-1)}
      />
      {error ? <span role="alert" className="type-label text-grade-rough">{error}</span> : null}
    </span>
  );
}
