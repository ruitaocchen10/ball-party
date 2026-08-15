"use client";

import { Button } from "@/components/ui/Button";
import { startRun } from "@/lib/lobbies/actions";

/**
 * The control that deals a Higher or Lower ladder.
 *
 * No format fields yet, deliberately. The two the host will eventually pick —
 * scoring mode and era window — are arguments of the start RPC already, and it
 * resolves them to season total over the whole pool when they are absent. The
 * picker is #29; sending nothing until then is a validated choice rather than
 * an unchecked path.
 *
 * Rendered for the host only, because a game beginning while somebody is still
 * explaining the rules is what the host-only rule exists to prevent. The rule
 * itself is `public.start_run`, which refuses anybody but the room's host;
 * `higher_or_lower.start` then checks that its caller is in the run. So this is
 * the honest rendering of a rule enforced upstream, not the rule.
 */
export function StartHigherOrLower({
  lobbyId,
  code,
  players,
}: {
  lobbyId: string;
  code: string;
  players: number;
}) {
  const short = players < 2;

  return (
    <form action={startRun} className="flex flex-col gap-2">
      <input type="hidden" name="lobby_id" value={lobbyId} />
      <input type="hidden" name="code" value={code} />
      <input type="hidden" name="game" value="higher_or_lower" />
      <Button type="submit" disabled={short}>
        Start higher or lower
      </Button>
      {short ? (
        <p className="font-mono text-[10px] tracking-[0.13em] text-fg-muted uppercase">
          Waiting for one more player
        </p>
      ) : null}
    </form>
  );
}
