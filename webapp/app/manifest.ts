import type { MetadataRoute } from "next";

import { SITE_DESCRIPTION, SITE_NAME } from "@/lib/seo/site";

export default function manifest(): MetadataRoute.Manifest {
  return {
    name: SITE_NAME,
    short_name: SITE_NAME,
    description: SITE_DESCRIPTION,
    start_url: "/",
    display: "standalone",
    // --surface in globals.css
    background_color: "#111311",
    theme_color: "#111311",
    icons: [{ src: "/brand/ball-party-mark-dark.png", sizes: "1024x1024", type: "image/png", purpose: "any" }],
  };
}
