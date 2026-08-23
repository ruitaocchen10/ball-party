"use client";

import { useEffect } from "react";
import { useRouter } from "next/navigation";

import { Concealed } from "@/components/ui/Concealed";
import { createRealtimeClient } from "@/lib/supabase/client";

/**
 * The moment between a run existing and its board being dealt.
 *
 * start_run does not call any game's setup — it does not know games exist — so
 * the two are separate transactions and this state is reachable. It is normally
 * a blink; it is rendered rather than hidden because a client that arrives
 * during it would otherwise see nothing at all.
 */
export function MatchSetup({ matchId }: { matchId: string }) {
  const router = useRouter();

  useEffect(() => {
    let cleanup: (() => void) | null = null;
    let cancelled = false;

    void (async () => {
      const supabase = await createRealtimeClient();
      if (cancelled) return;

      const channel = supabase
        .channel(`match-setup:${matchId}`)
        .on(
          "postgres_changes",
          { event: "UPDATE", schema: "public", table: "matches", filter: `id=eq.${matchId}` },
          () => router.refresh(),
        )
        // The server action normally deals before redirecting here, but the
        // match can still be read as `setup` from the first render. A change
        // that committed before this subscription existed would be missed, so
        // re-read once the channel is ready as well as on later updates.
        .subscribe((status) => {
          if (status === "SUBSCRIBED") router.refresh();
        });

      cleanup = () => {
        void supabase.removeChannel(channel);
      };
    })();

    return () => {
      cancelled = true;
      cleanup?.();
    };
  }, [matchId, router]);

  return (
    <Concealed label="Dealing the board" className="flex h-24 items-center">
      <span className="relative w-full text-center font-mono text-[10px] tracking-[0.15em] text-panel uppercase">
        Dealing the board
      </span>
    </Concealed>
  );
}
