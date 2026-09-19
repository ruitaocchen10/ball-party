import type { MetadataRoute } from "next";

import { fetchSitemapPrompts } from "@/lib/foundation/content/prompts/meta";
import { SITE_URL } from "@/lib/seo/site";

// Prompts arrive weekly, not by the second — an hour behind is fine and keeps
// crawlers from turning into one Supabase query each.
export const revalidate = 3600;

export default async function sitemap(): Promise<MetadataRoute.Sitemap> {
  const pages: MetadataRoute.Sitemap = [{ url: `${SITE_URL}/` }, { url: `${SITE_URL}/party` }];

  try {
    const prompts = await fetchSitemapPrompts();
    return [
      ...pages,
      ...prompts.map(({ id, updatedAt }) => ({ url: `${SITE_URL}/prompts/${id}`, lastModified: new Date(updatedAt) })),
    ];
  } catch (error) {
    // A Supabase outage shouldn't fail the build or 500 the sitemap; the static
    // pages are still worth serving until the next revalidation fills in the rest.
    console.error("sitemap: could not list prompts", error);
    return pages;
  }
}
