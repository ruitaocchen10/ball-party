/**
 * PROTOTYPE — throwaway. Hardcoded content standing in for the real
 * ingestion pipeline (teams, players, upcoming games) that a real composer
 * would pull an option pool from. The posts themselves are real now — see
 * lib/prompts/feed.ts — this file only still stands in for what a post's
 * options are built out of.
 */

import type { MockGame, Player, Team } from "./types";

export const TEAMS: Team[] = [
  { code: "BUF", name: "Bills", conference: "AFC", division: "AFC East" },
  { code: "MIA", name: "Dolphins", conference: "AFC", division: "AFC East" },
  { code: "NE", name: "Patriots", conference: "AFC", division: "AFC East" },
  { code: "NYJ", name: "Jets", conference: "AFC", division: "AFC East" },
  { code: "KC", name: "Chiefs", conference: "AFC", division: "AFC West" },
  { code: "LV", name: "Raiders", conference: "AFC", division: "AFC West" },
  { code: "LAC", name: "Chargers", conference: "AFC", division: "AFC West" },
  { code: "DEN", name: "Broncos", conference: "AFC", division: "AFC West" },
  { code: "SEA", name: "Seahawks", conference: "NFC", division: "NFC West" },
  { code: "SF", name: "49ers", conference: "NFC", division: "NFC West" },
  { code: "LA", name: "Rams", conference: "NFC", division: "NFC West" },
  { code: "ARI", name: "Cardinals", conference: "NFC", division: "NFC West" },
  { code: "PHI", name: "Eagles", conference: "NFC", division: "NFC East" },
  { code: "DAL", name: "Cowboys", conference: "NFC", division: "NFC East" },
  { code: "NYG", name: "Giants", conference: "NFC", division: "NFC East" },
  { code: "WAS", name: "Commanders", conference: "NFC", division: "NFC East" },
];

// Real headshot_url values, pulled from this project's own auction_lots
// table (NFL.com's CDN — the same source the auction and higher-or-lower
// games already render headshots from in production).
export const RUNNING_BACKS: Player[] = [
  { id: "rb-robinson", name: "Bijan Robinson", team: "ATL", position: "RB", headshotUrl: "https://static.www.nfl.com/image/upload/f_auto,q_auto/league/esii5yb8yn9edboi4mlq" },
  { id: "rb-gibbs", name: "Jahmyr Gibbs", team: "DET", position: "RB", headshotUrl: "https://static.www.nfl.com/image/upload/f_auto,q_auto/league/cursejnmmp1i9hnxihkj" },
  { id: "rb-barkley", name: "Saquon Barkley", team: "PHI", position: "RB", headshotUrl: "https://static.www.nfl.com/image/upload/f_auto,q_auto/league/qcayrzjpura2zydszonh" },
  { id: "rb-henry", name: "Derrick Henry", team: "BAL", position: "RB", headshotUrl: "https://static.www.nfl.com/image/upload/f_auto,q_auto/league/tm79x0iknqg6hms3ypyt" },
  { id: "rb-hall", name: "Breece Hall", team: "NYJ", position: "RB", headshotUrl: "https://static.www.nfl.com/image/upload/f_auto,q_auto/league/i01xtqbfajfq68lb6orh" },
];

export const UPCOMING_GAMES: MockGame[] = [
  { id: "g-buf-kc", home: "BUF", away: "KC", kickoff: "2026-09-14T20:20:00Z", label: "Chiefs @ Bills · SNF" },
  { id: "g-sea-ne", home: "SEA", away: "NE", kickoff: "2026-09-08T17:00:00Z", label: "Patriots @ Seahawks" },
  { id: "g-cin-bal", home: "CIN", away: "BAL", kickoff: "2026-09-15T00:15:00Z", label: "Ravens @ Bengals · MNF" },
  { id: "g-phi-dal", home: "PHI", away: "DAL", kickoff: "2026-09-21T17:00:00Z", label: "Cowboys @ Eagles" },
];
