import { createPublicClient } from "@/lib/supabase/public";
import { SITE_NAME, truncate } from "@/lib/seo/site";
import type { LifecycleStatus, TemplateKind } from "@/lib/foundation/content/prompts/types";

/**
 * What a prompt page needs to describe itself to a search engine or a link
 * preview — none of the slots, responses or comments that fetchPromptFeed
 * assembles. Everything here is already public (migration 0112), and none of
 * it names a player.
 */
export type PromptMeta = {
  id: string;
  title: string;
  description: string;
  templateName: string;
  status: LifecycleStatus;
  /** When the page's content last changed: resolution if it has one, else creation. */
  updatedAt: string;
};

/**
 * The kinds the Huddle on Home shows (see isHomePrompt in app/page.tsx).
 * Other kinds are composer-only for now, so they stay out of the sitemap
 * rather than advertising pages the product isn't presenting yet.
 */
export const INDEXABLE_TEMPLATE_KINDS: TemplateKind[] = ["picks", "game_pick", "weekly_picks", "power_rankings"];

/** Fallback when a post has no caption to lend the meta description. */
function fallbackDescription(templateName: string): string {
  return `${templateName} on ${SITE_NAME} — make your picks and see how you stack up against everyone else.`;
}

export function describePrompt(caption: string, templateName: string): string {
  const text = truncate(caption, 160);
  return text || fallbackDescription(templateName);
}

const PROMPT_META_COLUMNS = "id, prompt_text, caption, template_name, status, created_at, resolved_at";

/** Null for an unknown id, a malformed one, or any read error — callers treat all three as "no such page". */
export async function fetchPromptMeta(id: string): Promise<PromptMeta | null> {
  const { data } = await createPublicClient().from("prompt_posts").select(PROMPT_META_COLUMNS).eq("id", id).maybeSingle();
  if (!data) return null;

  return {
    id: data.id,
    title: data.prompt_text,
    description: describePrompt(data.caption, data.template_name),
    templateName: data.template_name,
    status: data.status as LifecycleStatus,
    updatedAt: data.resolved_at ?? data.created_at,
  };
}

/**
 * Every post worth listing in the sitemap: a kind the Huddle shows, and not void.
 * Throws on a read error so the sitemap can say so, rather than quietly
 * publishing a sitemap with no prompts in it.
 */
export async function fetchSitemapPrompts(limit = 5000): Promise<Pick<PromptMeta, "id" | "updatedAt">[]> {
  const { data, error } = await createPublicClient()
    .from("prompt_posts")
    .select("id, created_at, resolved_at")
    .in("template_kind", INDEXABLE_TEMPLATE_KINDS)
    .neq("status", "void")
    .order("created_at", { ascending: false })
    .limit(limit);
  if (error) throw error;

  return (data ?? []).map((row) => ({ id: row.id, updatedAt: row.resolved_at ?? row.created_at }));
}
