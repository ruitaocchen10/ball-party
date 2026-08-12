"use client";

import { AuctionScreen } from "../AuctionScreen";
import { SCENARIOS } from "../scenarios";

export function Frame({ state, secs, stamp }: { state?: string; secs?: string; stamp?: string }) {
  const scenario = SCENARIOS.find((s) => s.id === state) ?? SCENARIOS[0];
  const seconds = secs === undefined || secs === "" ? scenario.seconds : Number(secs);

  return (
    <div className="flex h-dvh flex-col bg-surface">
      <AuctionScreen
        scenario={scenario}
        remainingMs={seconds === null ? null : seconds * 1000}
        stamped={stamp === "1"}
      />
    </div>
  );
}
