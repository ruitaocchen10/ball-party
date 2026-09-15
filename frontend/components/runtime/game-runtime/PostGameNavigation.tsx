"use client";

import { useEffect } from "react";
import { useRouter } from "next/navigation";

import { createRealtimeClient } from "@/lib/runtime/realtime/client";

/** Follows the host's durable post-game choice in every player’s open tab. */
export function PostGameNavigation({
  matchId,
  roomCode,
}: {
  matchId: string;
  roomCode: string;
}) {
  const router = useRouter();

  useEffect(() => {
    let cleanup: (() => void) | null = null;
    let cancelled = false;

    void (async () => {
      const supabase = await createRealtimeClient();
      if (cancelled) return;
      const channel = supabase
        .channel(`post-game:${matchId}`)
        .on(
          "postgres_changes",
          { event: "INSERT", schema: "public", table: "post_game_actions", filter: `match_id=eq.${matchId}` },
          async (payload) => {
            const action = payload.new as { choice: "replay" | "lobby"; next_match_id: string | null };
            const destination = action.choice === "replay" && action.next_match_id
              ? `/match/${action.next_match_id}`
              : `/lobby/${roomCode}`;
            router.replace(destination);
          },
        )
        .subscribe();
      cleanup = () => { void supabase.removeChannel(channel); };
    })();

    return () => {
      cancelled = true;
      cleanup?.();
    };
  }, [matchId, roomCode, router]);

  return null;
}
