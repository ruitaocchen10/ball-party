import { AWARDS, AWARD_LABELS, PLAYOFF_LABELS, type SeasonResult } from "@/lib/games/qb-season-builder/result";

const thousands = (value: number) => value.toLocaleString("en-US");

/**
 * The deliberately small public projection for a finished season's link card.
 * It is built from `SeasonResult`, the completed-result API projection. This
 * function selects only public outcome fields, so draft choices, hidden-mode
 * values, source data, and branding cannot cross this boundary.
 */
export function shareCardFromResult(result: SeasonResult) {
  const awards = AWARDS.filter((award) => result.awards[award]).map((award) => AWARD_LABELS[award]);
  const statLine = `${thousands(result.statLine.passYards)} YDS · ${result.statLine.passTds} TD · ${result.statLine.interceptions} INT`;
  const record = `${result.record.wins}–${result.record.losses} RECORD`;
  const playoffs = PLAYOFF_LABELS[result.playoffs.result];
  const score = result.score.toFixed(1);

  return {
    title: "QB Season Builder",
    description: [
      `${thousands(result.statLine.passYards)} pass yards`,
      `${result.statLine.passTds} pass TD`,
      `${result.statLine.interceptions} INT`,
      `${result.record.wins}–${result.record.losses}`,
      playoffs,
      awards.length ? awards.join(", ") : "No awards",
      `${score} score`,
    ].join(" · "),
    statLine,
    record,
    playoffs,
    awards,
    score,
  };
}
