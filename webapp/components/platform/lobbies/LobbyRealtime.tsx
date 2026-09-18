"use client";

import { useEffect } from "react";
import { useRouter } from "next/navigation";

import { guestSessionFinishedHref } from "@/lib/foundation/identity/guest-lifecycle";
import { createRealtimeClient } from "@/lib/runtime/realtime/client";

/**
 * Re-fetches the server-rendered lobby whenever its durable state changes.
 * The database remains the source of truth, including the RLS decision about
 * which members may receive each event.
 *
 * `runs` and `matches` are here so that starting a game carries everyone into
 * it: the host's own navigation is a redirect, and everybody else finds out
 * because a run appeared in the room they are sitting in. The lobby page does
 * the navigating — this only tells it something changed.
 *
 * `matches` is subscribed unfiltered because a match is keyed on its run, which
 * this component does not know until one exists. RLS already scopes the stream
 * to matches of runs the subscriber is in, so unfiltered is not unguarded.
 *
 * A refresh per event is right here and wrong inside a match: see
 * components/auction/AuctionMatch.tsx, which applies payloads directly because
 * a server round trip per bid is the latency the game is built to avoid.
 */
export function LobbyRealtime({ lobbyId }: { lobbyId: string }) {
  const router = useRouter();

  useEffect(() => {
    const refresh = () => router.refresh();
    let cleanup: (() => void) | null = null;
    let cancelled = false;

    void (async () => {
      const supabase = await createRealtimeClient();
      if (cancelled) return;

      const channel = supabase
        .channel(`lobby:${lobbyId}`)
        .on(
          "postgres_changes",
          {
            event: "*",
            schema: "public",
            table: "lobby_members",
            filter: `lobby_id=eq.${lobbyId}`,
          },
          refresh,
        )
        .on(
          "postgres_changes",
          {
            event: "*",
            schema: "public",
            table: "lobbies",
            filter: `id=eq.${lobbyId}`,
          },
          (payload) => {
            if ((payload.new as { closed_at: string | null }).closed_at) {
              // The endpoint preserves an account session, but clears a
              // temporary player's anonymous session before returning home.
              // Going straight to `/` used to leave that player authenticated
              // after the party had ended.
              router.replace(guestSessionFinishedHref("/"));
              return;
            }
            refresh();
          },
        )
        .on(
          "postgres_changes",
          {
            event: "*",
            schema: "public",
            table: "runs",
            filter: `lobby_id=eq.${lobbyId}`,
          },
          refresh,
        )
        .on("postgres_changes", { event: "*", schema: "public", table: "matches" }, refresh)
        .subscribe();

      const heartbeat = () => {
        if (document.visibilityState === "visible") {
          void supabase.rpc("heartbeat_lobby", { p_lobby_id: lobbyId });
        }
      };
      heartbeat();
      const heartbeatInterval = window.setInterval(heartbeat, 10_000);
      document.addEventListener("visibilitychange", heartbeat);

      cleanup = () => {
        window.clearInterval(heartbeatInterval);
        document.removeEventListener("visibilitychange", heartbeat);
        void supabase.removeChannel(channel);
      };
    })();

    return () => {
      cancelled = true;
      cleanup?.();
    };
  }, [lobbyId, router]);

  return null;
}
