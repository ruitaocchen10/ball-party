import { render } from "@testing-library/react";

import { AuctionMatch } from "@/components/auction/AuctionMatch";
import type { Bid, Lot, Player, Standing, Turn } from "@/lib/auction/board";

import { MATCH, board, players, supabaseMock } from "./factories";

type Options = {
  turn: Turn;
  lots?: Lot[];
  seats?: Player[];
  bids?: Bid[];
  standings?: Standing[];
  /** Seat 0 by default; pass null to render as a non-participant spectator. */
  viewerId?: string | null;
};

/** Mounts the match screen with the shared supabase mock wired in. */
export function renderMatch(options: Options) {
  const supabase = supabaseMock();
  globalThis.__supabaseMock = supabase;

  const view = render(
    <AuctionMatch
      matchId={MATCH}
      viewerId={options.viewerId === undefined ? "u0" : (options.viewerId ?? "nobody")}
      displayName="Ava"
      roomCode="ABCD"
      initial={{
        turn: options.turn,
        serverNow: new Date().toISOString(),
        lots: options.lots ?? board(),
        players: options.seats ?? players(),
        bids: options.bids ?? [],
        standings: options.standings ?? [],
      }}
    />,
  );
  return { ...view, supabase };
}
