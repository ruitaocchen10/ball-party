/**
 * Domain types for the prompts feature (posts, slots, options, takes).
 * Not a durable Postgres schema — see docs/games/ for what a real game's
 * docs look like once prompt content has its own ingestion pipeline.
 */

export type SlotShape = "pick" | "pick_set" | "rank";

/** `game_pick` and `weekly_picks` remain readable for posts created before Picks unified them. */
export type TemplateKind = "picks" | "game_pick" | "weekly_picks" | "stat_leader" | "ranking" | "power_rankings" | "custom_multi";

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
  /** The author's choices, revealed only after the prompt has locked. */
  response?: Record<string, string[]>;
  /**
   * Replies to this comment, one level deep — a reply's own `replies` is
   * always empty, since prompts.post_comment refuses a reply to a reply.
   * Empty for a comment that hasn't been fetched as a top-level take.
   */
  replies: Comment[];
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
  /** No correct answer — do_resolve refuses to ever grade this post. Independent of templateKind. */
  isOpinion?: boolean;
  slots: Slot[];
  comments: Comment[];
  responseCount: number;
  viewerAnswered: boolean;
  viewerResponse?: Record<string, string[]>;
  /** Power Rankings only: the six teams the admin chose for the cover art, in placement order. */
  coverTeamCodes?: string[];
  /** Team-code → position from this viewer's most recent earlier Power Rankings submission. */
  previousRankByTeam?: Record<string, number>;
  viewerPointsAwarded?: number;
  /** slotId -> optionId -> percent of respondents who picked it. Shown once locked/resolved, or once the viewer has answered. */
  aggregate?: Record<string, Record<string, number>>;
  /** Consensus from all submitted Power Rankings: teams most often placed in a ballot's top five. */
  powerRankingTopFive?: { optionId: string; topFiveCount: number; averageRank: number }[];
};

export type Team = { code: string; name: string; conference: "AFC" | "NFC"; division: string };
export type Player = { id: string; name: string; team: string; position: string; headshotUrl: string };
