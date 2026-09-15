/**
 * Turns an AV number into a letter, A+ through F, the way people actually
 * read a team: nobody at the table knows what "93 AV" means, but everybody
 * knows what a B+ means.
 *
 * Both scales below are ultimately grounded in the same real dataset the
 * game itself drafts from (`private.av_roster_players`, 2006-2025, 29,782
 * player-seasons) -- but the cutoffs are percentiles of a simulated
 * population of *drafts* (spin-then-recognize-then-pick, at varying levels
 * of picker skill) rather than of the raw player pool, because the real
 * mechanic lets a picker reach further than the raw pool's own spread
 * implies. See the two functions' own comments for how each was actually
 * computed.
 */

/** Round 8-13's slot labels fold onto the AV pool's own (broader) category
 * the same way `sabotage_draft_private.pool_categories` folds RB1/RB2 and
 * WR1/WR2/WR3 server-side -- a pick's grade is read off its position's own
 * distribution, and the pool only has ten position buckets, not thirteen
 * slot labels. */
function categoryFor(slot: string): string {
  if (slot.startsWith("RB")) return "RB";
  if (slot.startsWith("WR")) return "WR";
  return slot;
}

export type Grade = "A+" | "A" | "A-" | "B+" | "B" | "B-" | "C+" | "C" | "C-" | "D+" | "D" | "D-" | "F";

/** Ascending order, the boundary an AV has to clear for each step up from
 * F -- see `letterFor`. F itself has no boundary of its own; it's just
 * "didn't clear the first one." */
const LADDER: Grade[] = ["D-", "D", "D+", "C-", "C", "C+", "B-", "B", "B+", "A-", "A", "A+"];

/**
 * Twelve cutoffs, not four: F stays a single band (nobody needs an F- to
 * know a season was replacement-level), but D/C/B/A above it each split
 * into three -- an even thirds-of-a-percentile-range cut, not a second
 * round of guessing.
 *
 * These are NOT percentiles of the raw player-season pool (that was the
 * first cut, and it graded too easily -- see the team cutoffs' comment for
 * why). A single spin's real pool is one franchise's *entire 2006-2025
 * history* at a position, and a picker who recognizes names reliably finds
 * that franchise's best-ever year at the position, not a random one. So
 * these are percentiles of a simulated population of pickers -- a mix of
 * pure-random, mildly-recognizing, moderately-recognizing, and
 * sharp-recognizing draws, one full population run per position -- which
 * is what a real spin-then-recognize pick actually produces. That's why a
 * merely "pretty good" pick now needs more AV to clear a given band than
 * the old pool-percentile cutoffs required: the achievable ceiling here is
 * higher than the raw pool's own spread suggested.
 *
 * Still position-relative for the same reason as before: a QB's ceiling
 * (best-ever season: 24 AV) is three times a special teamer's (best-ever:
 * 8 AV), so grading every position on one shared scale would make an elite
 * kicker look like a bust next to a merely decent quarterback.
 */
const POSITION_CUTOFFS: Record<string, number[]> = {
  QB: [3, 6, 7, 10, 12, 13, 15, 16, 17, 18, 19, 20],
  RB: [1, 3, 3, 5, 7, 9, 10, 12, 13, 16, 16, 18],
  WR: [2, 3, 4, 5, 7, 8, 10, 11, 12, 14, 15, 16],
  TE: [0, 1, 1, 2, 4, 5, 6, 7, 8, 9, 11, 12],
  OL: [3, 4, 5, 6, 7, 8, 9, 10, 11, 13, 14, 15],
  DL: [2, 4, 4, 6, 7, 8, 9, 11, 13, 15, 17, 18],
  LB: [2, 3, 4, 5, 7, 8, 9, 10, 12, 15, 16, 17],
  CB: [2, 3, 3, 4, 5, 6, 8, 9, 11, 13, 14, 16],
  S: [2, 3, 4, 5, 5, 6, 7, 8, 9, 11, 13, 13],
  ST: [1, 2, 2, 2, 3, 3, 4, 4, 4, 5, 5, 5],
};

/** Walks the ladder from the top: the highest grade whose cutoff the value
 * clears. `cutoffs` and `LADDER` are the same length and both ascending,
 * so the first (lowest) cutoff cleared from the top down names the grade. */
function letterFor(av: number, cutoffs: number[]): Grade {
  for (let i = cutoffs.length - 1; i >= 0; i--) {
    if (av >= cutoffs[i]) return LADDER[i];
  }
  return "F";
}

/** A single drafted player's grade, relative to real players at their own
 * position (`slot` is the round's label -- "RB1", "WR2", "ST", etc). */
export function gradeForPick(slot: string, av: number): Grade {
  const cutoffs = POSITION_CUTOFFS[categoryFor(slot)];
  return letterFor(av, cutoffs ?? POSITION_CUTOFFS.QB);
}

/**
 * A whole roster's grade -- not read off the table it was drafted at
 * (see `sabotage_draft_private.baseline_roster_strength`'s own comment for
 * why that self-cancels). The *center* of the scale is still that fixed
 * real-world baseline (93, the average real NFL team's best starter at
 * each of the thirteen slots) -- that constant doesn't move, and it's
 * still exactly what the season simulator plays every roster against, so a
 * middling grade and a middling record keep telling the same story.
 *
 * But the cutoffs themselves are NOT percentiles of that real-team
 * distribution anymore -- they were originally, and it graded too easily.
 * A real team-season is capped at 160 (2007 Patriots) because all thirteen
 * starters had to come from one roster in one year. A drafted roster isn't
 * capped there: each of the thirteen rounds spins an independent franchise
 * and draws from that franchise's entire 2006-2025 history, so a picker
 * who recognizes names can stack thirteen different franchises' best-ever
 * years at each slot -- a ceiling real teams never had access to. Grading
 * against the real-team spread meant a solidly-played draft cleared the
 * old A+ cutoff (127) too easily to mean much.
 *
 * So these cutoffs are percentiles of a simulated population of drafts
 * instead -- a mix of pure-random, mildly-recognizing, moderately-
 * recognizing, and sharp-recognizing pickers, run through the real
 * spin-then-pick mechanic -- built so its *mean* still lands on 93 (the
 * scale isn't shifted) but its *spread* is wider, because that's what the
 * mechanic actually produces once a competent picker is behind it. The
 * practical effect: the best roster ever actually drafted in this game so
 * far (126 AV) now grades A-, not A -- strong, but with real room left
 * above it, instead of maxing out the scale.
 */
const TEAM_CUTOFFS = [60, 69, 72, 82, 93, 102, 110, 114, 120, 126, 130, 136];

export function gradeForTeam(rosterStrength: number): Grade {
  return letterFor(rosterStrength, TEAM_CUTOFFS);
}
