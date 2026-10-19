"use client";

import { useEffect, useState } from "react";
import { useRouter } from "next/navigation";

import { track } from "@/lib/foundation/analytics/client";
import { createClient } from "@/lib/supabase/client";
import { joinLobbyFromBrowser } from "@/lib/platform/lobbies/client";
import { lobbyErrorMessage } from "@/lib/platform/lobbies/messages";

/** Joins an authenticated invitee without interposing a second confirmation. */
export function AutoJoinRoom({ code }: { code: string }) {
  const router = useRouter();
  const [error, setError] = useState<string | null>(null);

  useEffect(() => {
    let active = true;
    const supabase = createClient();
    // join_lobby is idempotent, so Strict Mode or a Fast Refresh retry cannot
    // give a viewer two seats.
    void joinLobbyFromBrowser(supabase, code).then(({ error: joinError }) => {
      if (!active) return;
      if (joinError) {
        setError(lobbyErrorMessage(joinError.message));
        return;
      }
      track("party_joined", {});
      router.refresh();
    });
    return () => { active = false; };
  }, [code, router]);

  return error ? (
    <p role="alert" className="text-sm text-hidden-text">{error}</p>
  ) : (
    <p className="text-sm leading-6 text-fg-muted">Joining room…</p>
  );
}
