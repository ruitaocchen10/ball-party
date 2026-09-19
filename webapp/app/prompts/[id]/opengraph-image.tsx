import { fetchPromptMeta } from "@/lib/foundation/content/prompts/meta";
import type { LifecycleStatus } from "@/lib/foundation/content/prompts/types";
import { renderOgCard } from "@/lib/seo/og-card";

export const alt = "A Ball Party prompt";
export const size = { width: 1200, height: 630 };
export const contentType = "image/png";

// Rendered per request (the id is dynamic), so Next won't cache it itself. The
// status chip moves from open to resolved over a week; an hour of CDN staleness is fine.
const CACHE_CONTROL = "public, max-age=0, s-maxage=3600, stale-while-revalidate=86400";

const BADGES: Partial<Record<LifecycleStatus, { label: string; filled?: boolean }>> = {
  open: { label: "Open" },
  locked: { label: "Locked" },
  resolved: { label: "Results in", filled: true },
};

/**
 * The preview card for a shared prompt link. Also inherited by the take pages
 * under it, which is what a shared take link should show anyway. An unknown id
 * gets the generic card rather than an error, so a mistyped link still unfurls.
 */
export default async function Image({ params }: { params: Promise<{ id: string }> }) {
  const { id } = await params;
  const meta = await fetchPromptMeta(id);
  if (!meta) {
    return renderOgCard({ title: "Sports knowledge party games", eyebrow: "Play with your friends", cacheControl: CACHE_CONTROL });
  }

  return renderOgCard({ title: meta.title, eyebrow: meta.templateName, badge: BADGES[meta.status], cacheControl: CACHE_CONTROL });
}
