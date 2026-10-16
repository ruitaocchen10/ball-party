// What the daily schedule email says. Pure: the Edge Function fetches the
// items (public.claim_schedule_digest, migration 0215) and sends what this
// returns, so the wording can be tested without a database or a mail provider.

export interface DigestItem {
  id: string;
  kind: string;
  game_id: string | null;
  state: string;
  due_at: string | null;
  lock_at: string | null;
  /** The manual step still missing, or why opening failed. */
  attention: string | null;
  /** Due on today's date, US Eastern. */
  today: boolean;
}

const KIND_LABELS: Record<string, string> = {
  game_pick: "Game picks",
  weekly_picks: "Weekly picks",
  weekly_awards: "Weekly awards",
  bold_predictions: "Bold predictions",
  power_rankings: "Power rankings",
};

/** nflverse ids read season_week_away_home: "2026_05_BUF_KC" is BUF at KC. */
export function itemTitle(item: Pick<DigestItem, "kind" | "game_id">): string {
  const [, week, away, home] = (item.game_id ?? "").split("_");
  const kind = KIND_LABELS[item.kind] ?? item.kind;
  return away && home ? `${kind}: ${away} @ ${home} (week ${Number(week)})` : kind;
}

function when(iso: string | null): string {
  if (!iso) return "no time set";
  return new Intl.DateTimeFormat("en-US", {
    timeZone: "America/New_York",
    weekday: "short",
    month: "short",
    day: "numeric",
    hour: "numeric",
    minute: "2-digit",
  }).format(new Date(iso));
}

function line(item: DigestItem): string {
  return `- ${itemTitle(item)}, due ${when(item.due_at)} ET [${item.state}]: ${item.attention ?? "needs attention"}`;
}

export function renderDigest(items: DigestItem[], adminUrl?: string): { subject: string; text: string } {
  const today = items.filter((item) => item.today);
  const soon = items.filter((item) => !item.today);
  const sections: string[] = [];
  if (today.length) sections.push(`Opens today and isn't ready:\n${today.map(line).join("\n")}`);
  if (soon.length) sections.push(`Opens in the next 2 days and isn't ready:\n${soon.map(line).join("\n")}`);
  if (adminUrl) sections.push(`Open the calendar: ${adminUrl}`);
  const count = items.length;
  return {
    subject: `${count} prompt${count === 1 ? "" : "s"} need${count === 1 ? "s" : ""} attention`,
    text: sections.join("\n\n"),
  };
}
