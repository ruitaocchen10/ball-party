"use client";

import { Button } from "@/components/foundation/ui-kit/Button";
import { startRun } from "@/lib/platform/lobbies/actions";

export function StartSabotageDraft({ lobbyId, code, players }: { lobbyId: string; code: string; players: number }) {
  const short = players < 2;
  return <form action={startRun} className="flex flex-col gap-2">
    <input type="hidden" name="lobby_id" value={lobbyId} />
    <input type="hidden" name="code" value={code} />
    <input type="hidden" name="game" value="sabotage_draft" />
    <Button type="submit" disabled={short}>Start sabotage draft</Button>
    {short ? <p className="font-mono text-[10px] tracking-[.13em] text-fg-muted uppercase">Waiting for one more player</p> : null}
  </form>;
}
