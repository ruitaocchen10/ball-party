import type { SupabaseClient } from "@supabase/supabase-js";

import { nflTeamName, type NflScheduleGame } from "@/lib/foundation/content/nfl/schedule";
import { promptErrorMessage } from "@/lib/foundation/content/prompts/messages";
import type { PlayerResult } from "@/lib/foundation/content/prompts/players";
import type { Database } from "@/lib/supabase/database.types";

/** Both limits are enforced again by 0171; these only keep the form honest. */
export const MAX_BOLD_PREDICTIONS = 5;
export const BOLD_BODY_MAX = 280;

export type BoldTargetType = "matchup" | "team" | "player";

/** The one required tag on a prediction: a game id, a team code or a player id, by `type`. */
export type BoldTarget = { type: BoldTargetType; id: string };

export type BoldPrediction = {
  id: string;
  author: string;
  authorUsername: string | null;
  isViewer: boolean;
  body: string;
  target: BoldTarget;
  createdAt: string;
};

/**
 * Everything the board needs to draw a tag: the week's games for matchup
 * tags, and the directory rows for whichever players the predictions name.
 * Teams need no lookup — their names and art come from the code alone.
 */
export type BoldPredictionBoardData = {
  predictions: BoldPrediction[];
  weekGames: NflScheduleGame[];
  players: Record<string, PlayerResult>;
};

export type TargetDescription = { label: string; teamCodes: string[]; player: PlayerResult | null };

/** The chip text and art for a tag; a target it can't resolve still gets a label rather than vanishing. */
export function describeTarget(target: BoldTarget, data: Pick<BoldPredictionBoardData, "weekGames" | "players">): TargetDescription {
  if (target.type === "team") return { label: nflTeamName(target.id), teamCodes: [target.id], player: null };
  if (target.type === "matchup") {
    const game = data.weekGames.find((candidate) => candidate.id === target.id);
    return game
      ? { label: game.label, teamCodes: [game.away, game.home], player: null }
      : { label: "Matchup", teamCodes: [], player: null };
  }
  const player = data.players[target.id] ?? null;
  return { label: player?.name ?? "Player", teamCodes: [], player };
}

type Client = SupabaseClient<Database>;
type PredictionRow = Database["public"]["Tables"]["bold_predictions"]["Row"];

export function toBoldPrediction(row: PredictionRow, viewerId: string | null, nameById: Map<string, string>, usernameById: Map<string, string | null>): BoldPrediction {
  return {
    id: row.id,
    author: nameById.get(row.author_id) ?? "Unknown",
    authorUsername: usernameById.get(row.author_id) ?? null,
    isViewer: row.author_id === viewerId,
    body: row.body,
    target: { type: row.target_type as BoldTargetType, id: row.target_id },
    createdAt: row.created_at,
  };
}

/** The whole response, saved at once and final: there is no editing or deleting afterwards. */
export async function submitBoldPredictions(
  supabase: Client,
  { postId, predictions }: { postId: string; predictions: { body: string; target: BoldTarget }[] },
): Promise<{ error: string | null }> {
  const { error } = await supabase.schema("prompts").rpc("submit_bold_predictions", {
    p_post_id: postId,
    p_predictions: predictions.map(({ body, target }) => ({ body, target_type: target.type, target_id: target.id })),
  });
  return { error: error ? promptErrorMessage(error.message) : null };
}
