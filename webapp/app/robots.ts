import type { MetadataRoute } from "next";

import { SITE_URL } from "@/lib/seo/site";

/**
 * Only what a crawler could never usefully read is disallowed: the admin
 * console and the signed-in account screens. Pages that should stay out of the
 * index but are fine to fetch — sign-in, invite links, take threads — are
 * `noindex` in their own metadata instead. A disallowed URL is never fetched,
 * so a crawler would never see the noindex there.
 */
export default function robots(): MetadataRoute.Robots {
  return {
    rules: {
      userAgent: "*",
      allow: "/",
      disallow: ["/admin", "/auth/", "/profile", "/settings", "/match/"],
    },
    sitemap: `${SITE_URL}/sitemap.xml`,
  };
}
