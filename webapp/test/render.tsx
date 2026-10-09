import { render } from "@testing-library/react";

import { AuctionMatch } from "@/components/games/auction/AuctionMatch";
import type { AuctionFormat, Bid, Lot, Player, ScoutHint, SealedBid, SealedBidStatus, Standing, Turn } from "@/lib/games/auction/board";

import { MATCH, board, players, supabaseMock } from "./factories";

type Options = {
  turn: Turn;
  lots?: Lot[];
  seats?: Player[];
  bids?: Bid[];
  standings?: Standing[];
  scoutHints?: ScoutHint[];
  sealedBids?: SealedBid[];
  sealedStatuses?: SealedBidStatus[];
  format?: AuctionFormat | null;
  /** Seat 0 by default; pass null to render as a non-participant spectator. */
  viewerId?: string | null;
  /** False by default. Only the host gets a pause control. */
  isHost?: boolean;
  /** False by default — the match is running. */
  paused?: boolean;
  /** False by default. True renders the final screen even if turn.currentLot
   *  has not yet passed turn.lotCount -- since 0090 a match can finish with
   *  lots still undealt. */
  complete?: boolean;
};

/** Mounts the match screen with the shared supabase mock wired in. */
export function renderMatch(options: Options) {
  const supabase = supabaseMock();
  globalThis.__supabaseMock = supabase;

  const view = render(
    <AuctionMatch
      matchId={MATCH}
      viewerId={options.viewerId === undefined ? "u0" : (options.viewerId ?? "nobody")}
      roomCode="ABCD"
      isHost={options.isHost ?? false}
      paused={options.paused ?? false}
      complete={options.complete ?? false}
      initial={{
        turn: options.turn,
        serverNow: new Date().toISOString(),
        lots: options.lots ?? board(),
        players: options.seats ?? players(),
        bids: options.bids ?? [],
        standings: options.standings ?? [],
        scoutHints: options.scoutHints ?? [],
        sealedBids: options.sealedBids ?? [],
        sealedStatuses: options.sealedStatuses ?? [],
        format: options.format ?? null,
      }}
    />,
  );
  return { ...view, supabase };
}
