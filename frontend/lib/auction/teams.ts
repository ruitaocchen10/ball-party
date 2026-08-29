import { teamLogoCode } from "@/lib/nfl/team-logos";

/** Returns null for an unexpected pool code so callers can remain text-first. */
export function auctionLogoCode(team: string): string | null {
  return teamLogoCode(team);
}
