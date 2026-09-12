/**
 * PROTOTYPE — throwaway. Types for the "ball knowledge" prompt-post feature
 * explored in components/social/. Nothing here is durable schema;
 * see docs/games/ for what a real game's docs look like once this ships.
 */

export type SlotShape = "pick" | "pick_set" | "rank";

/** `game_pick` and `weekly_picks` remain readable for posts created before Picks unified them. */
export type TemplateKind = "picks" | "game_pick" | "weekly_picks" | "stat_leader" | "ranking" | "custom_multi";

export type LifecycleStatus = "open" | "locked" | "resolved" | "void";

export type Option = {
  id: string;
  label: string;
  sublabel?: string;
  teamCode?: string;
  headshotUrl?: string;
  /** Both clubs when an option represents a matchup rather than one team. */
  teamCodes?: string[];
  position?: string;
};

export type Slot = {
  id: string;
  label: string;
  shape: SlotShape;
  options: Option[];
  /** How many options the viewer must select or order. */
  pickCount?: number;
  /** Points this slot is worth at full credit. */
  points: number;
  /** Ground truth. Unset until the pipeline (or an admin) resolves it. Order matters for `rank`. */
  correct?: string[];
  /** Slot ids whose already-chosen options this slot may not reuse — the preseason-picks constraint. */
  excludesSlotIds?: string[];
  /** nflverse game identity for an automatically graded winner pick. */
  sourceGameId?: string;
};

/** Schedule details shown on a matchup cover, indexed by a slot's source game. */
export type MatchupGameContext = {
  id: string;
  stadium: string;
  kickoff: string;
  primetime: boolean;
};

export type Comment = {
  id: string;
  author: string;
  body: string;
  createdAt: string;
  /** True only for the signed-in reader's comment. */
  isViewer: boolean;
  /** Whether the take was submitted at the same time as a pick. */
  postedWithPick: boolean;
};

export type Post = {
  id: string;
  templateKind: TemplateKind;
  templateName: string;
  author: string;
  caption: string;
  createdAt: string;
  promptText: string;
  resolutionCriteria: string;
  lockAt: string;
  status: LifecycleStatus;
  voidReason?: string;
  slots: Slot[];
  comments: Comment[];
  responseCount: number;
  viewerAnswered: boolean;
  viewerResponse?: Record<string, string[]>;
  viewerPointsAwarded?: number;
  /** slotId -> optionId -> percent of respondents who picked it. Shown once locked/resolved, or once the viewer has answered. */
  aggregate?: Record<string, Record<string, number>>;
};

export type Team = { code: string; name: string; conference: "AFC" | "NFC"; division: string };
export type Player = { id: string; name: string; team: string; position: string; headshotUrl: string };
export type MockGame = { id: string; home: string; away: string; kickoff: string; label: string };
