"use client";

import { useEffect } from "react";
import { useRouter } from "next/navigation";

import { createClient } from "@/lib/supabase/client";

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
    const supabase = createClient();
    const refresh = () => router.refresh();

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
        refresh,
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

    return () => {
      supabase.removeChannel(channel);
    };
  }, [lobbyId, router]);

  return null;
}
