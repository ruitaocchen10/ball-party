/** A kind of list a player can keep (ranking_list_kinds): Power Rankings, QBs and so on. */
export type ListKind = {
  id: string;
  label: string;
  /** Teams are keyed by nflverse code, players by player id. */
  itemKind: "team" | "player";
  /** The lengths the list may have. The database decides; the editor offers these. */
  sizes: number[];
};

/** A player's list as the Lists tab shows it: the newest version of one kind. */
export type ListSummary = {
  kind: string;
  label: string;
  itemKind: "team" | "player";
  versionId: string;
  versionNo: number;
  savedAt: string;
  versionCount: number;
  items: string[];
  /** The newest version's note. Only the owner and their friends get it. */
  note: string | null;
  /** The version it replaced, for movement marks. Null on a first version. */
  previousItems: string[] | null;
};

/** One saved version in a list's history. */
export type ListVersion = {
  id: string;
  versionNo: number;
  /** `prompt` when it came from answering a ranking prompt, `edit` when the player saved it. */
  source: "edit" | "prompt";
  promptPostId: string | null;
  /** The friends-only card, once the player posted this version. */
  updatePostId: string | null;
  note: string | null;
  savedAt: string;
  isCurrent: boolean;
  items: string[];
};

/** A player in a list: identity only, as ranking_players returns it. */
export type ListPlayer = { id: string; name: string; position: string; team: string; headshotUrl: string | null };

/** A published edit in the home feed, with the list it replaced. */
export type ListUpdate = {
  postId: string;
  authorId: string;
  username: string | null;
  displayName: string;
  avatarUrl: string | null;
  kind: string;
  label: string;
  itemKind: "team" | "player";
  versionNo: number;
  note: string | null;
  savedAt: string;
  items: string[];
  previousItems: string[] | null;
};
