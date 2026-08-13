import type { Bid, Lot, Player, Standing, Turn } from "@/lib/auction/board";

/**
 * A whole auction, frozen — the data half of the dummy page next door.
 *
 * Every one of the twenty player-weeks below is a REAL row: name, position,
 * season, week, team, opponent, points and headshot all come out of migrations
 * 0008 and 0013, pulled by player_id rather than typed from memory. The only
 * invented numbers are the prices and who won what, which is the auction this
 * fixture is pretending happened.
 *
 * Nothing here talks to Supabase. That is the point: the page renders states
 * you would otherwise have to play a real four-handed match to reach.
 */

const MATCH = "dev-match";
const RESOLVED = "2026-08-11T00:00:00Z";

export const VIEWER_ID = "u-dev";

export const PLAYERS: Player[] = [
  { user_id: "u-maria", seat: 1, budget: 20, match_id: MATCH, display_name: "Maria" },
  { user_id: "u-dev", seat: 2, budget: 20, match_id: MATCH, display_name: "Dev" },
  { user_id: "u-toby", seat: 3, budget: 20, match_id: MATCH, display_name: "Toby" },
  { user_id: "u-jules", seat: 4, budget: 20, match_id: MATCH, display_name: "Jules" },
];

/** All twenty lots, fully resolved. Scenarios below un-resolve the tail. */
const RESOLVED_LOTS: Lot[] = [
  { seq: 1, player_id: "00-0033873", display_name: "Patrick Mahomes", position: "QB",
    season: 2018, week: 11, team: "KC", opponent: "LA",
    is_flex: false, slot: "QB", points: 35.9, price: 6,
    winner_id: "u-dev", resolved_at: RESOLVED, headshot_url: "https://static.www.nfl.com/image/upload/f_auto,q_auto/league/wdckwtob1lybvkmxnf7p", match_id: MATCH },
  { seq: 2, player_id: "00-0023459", display_name: "Aaron Rodgers", position: "QB",
    season: 2011, week: 3, team: "GB", opponent: "CHI",
    is_flex: false, slot: "QB", points: 22.2, price: 0,
    winner_id: "u-maria", resolved_at: RESOLVED, headshot_url: "https://static.www.nfl.com/image/upload/f_auto,q_auto/league/dypvakakxhccxs67tb0y", match_id: MATCH },
  { seq: 3, player_id: "00-0029263", display_name: "Russell Wilson", position: "QB",
    season: 2017, week: 10, team: "SEA", opponent: "ARI",
    is_flex: false, slot: "QB", points: 19.4, price: 5,
    winner_id: "u-toby", resolved_at: RESOLVED, headshot_url: "https://static.www.nfl.com/image/upload/f_auto,q_auto/league/vkstxj0evgkjiycu4glc", match_id: MATCH },
  { seq: 4, player_id: "00-0034857", display_name: "Josh Allen", position: "QB",
    season: 2020, week: 13, team: "BUF", opponent: "SF",
    is_flex: false, slot: "QB", points: 30.1, price: 7,
    winner_id: "u-jules", resolved_at: RESOLVED, headshot_url: "https://static.www.nfl.com/image/upload/f_auto,q_auto/league/mjwbioajzldkq1vzoz2d", match_id: MATCH },
  { seq: 5, player_id: "00-0032241", display_name: "Todd Gurley", position: "RB",
    season: 2017, week: 15, team: "LA", opponent: "SEA",
    is_flex: false, slot: "RB", points: 45.0, price: 6,
    winner_id: "u-toby", resolved_at: RESOLVED, headshot_url: "https://static.www.nfl.com/image/private/f_auto,q_auto/league/jkqn4zynfdfvu359ygtr", match_id: MATCH },
  { seq: 6, player_id: "00-0032764", display_name: "Derrick Henry", position: "RB",
    season: 2020, week: 12, team: "TEN", opponent: "IND",
    is_flex: false, slot: "RB", points: 38.5, price: 4,
    winner_id: "u-maria", resolved_at: RESOLVED, headshot_url: "https://static.www.nfl.com/image/upload/f_auto,q_auto/league/tm79x0iknqg6hms3ypyt", match_id: MATCH },
  { seq: 7, player_id: "00-0026213", display_name: "Jamaal Charles", position: "RB",
    season: 2013, week: 15, team: "KC", opponent: "OAK",
    is_flex: false, slot: "RB", points: 59.5, price: 3,
    winner_id: "u-dev", resolved_at: RESOLVED, headshot_url: "https://static.www.nfl.com/image/private/f_auto,q_auto/league/mdrlzgankwwjldxllgcx", match_id: MATCH },
  { seq: 8, player_id: "00-0033045", display_name: "Ezekiel Elliott", position: "RB",
    season: 2018, week: 9, team: "DAL", opponent: "TEN",
    is_flex: false, slot: "RB", points: 15.2, price: 1,
    winner_id: "u-jules", resolved_at: RESOLVED, headshot_url: "https://static.www.nfl.com/image/upload/f_auto,q_auto/league/d4yr6htg4dbs0bgcfqnd", match_id: MATCH },
  { seq: 9, player_id: "00-0027944", display_name: "Julio Jones", position: "WR",
    season: 2015, week: 8, team: "ATL", opponent: "TB",
    is_flex: false, slot: "WR", points: 32.2, price: 5,
    winner_id: "u-maria", resolved_at: RESOLVED, headshot_url: "https://static.www.nfl.com/image/upload/f_auto,q_auto/league/omrddf2phtyztzx2nup1", match_id: MATCH },
  { seq: 10, player_id: "00-0031381", display_name: "Davante Adams", position: "WR",
    season: 2020, week: 6, team: "GB", opponent: "TB",
    is_flex: false, slot: "WR", points: 12.1, price: 2,
    winner_id: "u-toby", resolved_at: RESOLVED, headshot_url: "https://static.www.nfl.com/image/upload/f_auto,q_auto/league/tdzluk4xau3arxqk9zsl", match_id: MATCH },
  { seq: 11, player_id: "00-0031544", display_name: "Amari Cooper", position: "WR",
    season: 2019, week: 12, team: "DAL", opponent: "NE",
    is_flex: false, slot: "WR", points: 0.0, price: 0,
    winner_id: "u-jules", resolved_at: RESOLVED, headshot_url: "https://static.www.nfl.com/image/upload/f_auto,q_auto/league/zmtzqznqui37unmo5xv9", match_id: MATCH },
  { seq: 12, player_id: "00-0031588", display_name: "Stefon Diggs", position: "WR",
    season: 2020, week: 4, team: "BUF", opponent: "LV",
    is_flex: false, slot: "WR", points: 17.5, price: 4,
    winner_id: "u-dev", resolved_at: RESOLVED, headshot_url: "https://static.www.nfl.com/image/upload/f_auto,q_auto/league/cemcexmscsarpvwhafln", match_id: MATCH },
  { seq: 13, player_id: "00-0027656", display_name: "Rob Gronkowski", position: "TE",
    season: 2014, week: 11, team: "NE", opponent: "IND",
    is_flex: false, slot: "TE", points: 17.1, price: 5,
    winner_id: "u-dev", resolved_at: RESOLVED, headshot_url: "https://static.www.nfl.com/image/private/f_auto,q_auto/league/svpo7chliiymc0r7hegp", match_id: MATCH },
  { seq: 14, player_id: "00-0030506", display_name: "Travis Kelce", position: "TE",
    season: 2020, week: 8, team: "KC", opponent: "NYJ",
    is_flex: false, slot: "TE", points: 24.9, price: 1,
    winner_id: "u-toby", resolved_at: RESOLVED, headshot_url: "https://static.www.nfl.com/image/upload/f_auto,q_auto/league/dpxovcfku6ud2aohgf6a", match_id: MATCH },
  { seq: 15, player_id: "00-0030061", display_name: "Zach Ertz", position: "TE",
    season: 2018, week: 5, team: "PHI", opponent: "MIN",
    is_flex: false, slot: "TE", points: 27.0, price: 3,
    winner_id: "u-maria", resolved_at: RESOLVED, headshot_url: "https://static.www.nfl.com/image/upload/f_auto,q_auto/league/xktmmeumuoglbuam75iz", match_id: MATCH },
  { seq: 16, player_id: "00-0027696", display_name: "Jimmy Graham", position: "TE",
    season: 2019, week: 14, team: "GB", opponent: "WAS",
    is_flex: false, slot: "TE", points: 7.9, price: 0,
    winner_id: "u-jules", resolved_at: RESOLVED, headshot_url: "https://static.www.nfl.com/image/private/f_auto,q_auto/league/h7xs06oj6g03mippwtse", match_id: MATCH },
  { seq: 17, player_id: "00-0033906", display_name: "Alvin Kamara", position: "RB",
    season: 2020, week: 16, team: "NO", opponent: "MIN",
    is_flex: true, slot: "FLEX", points: 56.2, price: 0,
    winner_id: "u-toby", resolved_at: RESOLVED, headshot_url: "https://static.www.nfl.com/image/upload/f_auto,q_auto/league/yxebpuskandivlh2iil4", match_id: MATCH },
  { seq: 18, player_id: "00-0033040", display_name: "Tyreek Hill", position: "WR",
    season: 2018, week: 14, team: "KC", opponent: "BAL",
    is_flex: true, slot: "FLEX", points: 22.5, price: 4,
    winner_id: "u-maria", resolved_at: RESOLVED, headshot_url: "https://static.www.nfl.com/image/upload/f_auto,q_auto/league/gg73gnfivrn80oyqwazl", match_id: MATCH },
  { seq: 19, player_id: "00-0031408", display_name: "Mike Evans", position: "WR",
    season: 2019, week: 10, team: "TB", opponent: "ARI",
    is_flex: true, slot: "FLEX", points: 12.2, price: 2,
    winner_id: "u-jules", resolved_at: RESOLVED, headshot_url: "https://static.www.nfl.com/image/upload/f_auto,q_auto/league/zc4ujpmndyxrbiyyjomz", match_id: MATCH },
  { seq: 20, player_id: "00-0033908", display_name: "Cooper Kupp", position: "WR",
    season: 2021, week: 12, team: "LA", opponent: "GB",
    is_flex: true, slot: "FLEX", points: 18.6, price: 2,
    winner_id: "u-dev", resolved_at: RESOLVED, headshot_url: "https://static.www.nfl.com/image/upload/f_auto,q_auto/league/kjixprihktsfog6wx9sq", match_id: MATCH },
]

/** Lots as they stand partway through: everything after `upTo` is still sealed. */
export function lotsThrough(upTo: number): Lot[] {
  return RESOLVED_LOTS.map((lot) =>
    lot.seq <= upTo
      ? lot
      : { ...lot, winner_id: null, price: null, points: null, slot: null, resolved_at: null },
  );
}

export const ALL_LOTS = RESOLVED_LOTS;

/** Budgets after the lots up to and including `upTo` have been paid for. */
export function playersAfter(upTo: number): Player[] {
  return PLAYERS.map((player) => ({
    ...player,
    budget:
      20 -
      RESOLVED_LOTS.filter((lot) => lot.seq <= upTo && lot.winner_id === player.user_id).reduce(
        (sum, lot) => sum + (lot.price ?? 0),
        0,
      ),
  }));
}

export const STANDINGS: Standing[] = [
  { user_id: "u-toby", raw_score: 157.6, placement: 1, points_awarded: 3, match_id: MATCH, run_id: "dev-run", team: null },
  { user_id: "u-dev", raw_score: 148.6, placement: 2, points_awarded: 2, match_id: MATCH, run_id: "dev-run", team: null },
  { user_id: "u-maria", raw_score: 142.4, placement: 3, points_awarded: 1, match_id: MATCH, run_id: "dev-run", team: null },
  { user_id: "u-jules", raw_score: 65.4, placement: 4, points_awarded: 0, match_id: MATCH, run_id: "dev-run", team: null },
];

let bidSeq = 0;
const raise = (seq: number, user: string, price: number): Bid =>
  ({ seq, user_id: user, action: "raise", price, bid_seq: ++bidSeq, by_timeout: false, automatic: false, created_at: RESOLVED, match_id: MATCH });
const pass = (seq: number, user: string): Bid =>
  ({ seq, user_id: user, action: "pass", price: null, bid_seq: ++bidSeq, by_timeout: false, automatic: false, created_at: RESOLVED, match_id: MATCH });

export const BIDS = { raise, pass };

export const turn = (over: Partial<Turn> = {}): Turn => ({
  lotCount: 20,
  currentLot: 7,
  turnSeat: 2,
  openerSeat: 4,
  turnDeadline: null,
  phase: "bidding",
  phaseDeadline: null,
  ...over,
});
