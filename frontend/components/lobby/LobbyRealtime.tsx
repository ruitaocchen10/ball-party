"use client";

import { useEffect } from "react";
import { useRouter } from "next/navigation";

import { createClient } from "@/lib/supabase/client";

/**
 * Re-fetches the server-rendered lobby whenever its durable state changes.
 * The database remains the source of truth, including the RLS decision about
 * which members may receive each event.
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
      .subscribe();

    return () => {
      supabase.removeChannel(channel);
    };
  }, [lobbyId, router]);

  return null;
}
