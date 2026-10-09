import { describe, expect, it, vi } from "vitest";

// proxy.ts pulls in the Supabase session helper at import time; only its
// exported matcher is under test here.
vi.mock("@/lib/supabase/proxy", () => ({ updateSession: vi.fn() }));

import { config } from "./proxy";

/** Next compiles matchers with path-to-regexp; for this pattern a plain anchored RegExp is equivalent. */
const matcher = new RegExp(`^${config.matcher[0]}$`);
const runsProxy = (path: string) => matcher.test(path);

describe("proxy matcher", () => {
  it.each(["/robots.txt", "/sitemap.xml", "/manifest.webmanifest", "/opengraph-image", "/opengraph-image-1a2b3c", "/twitter-image", "/.well-known/apple-app-site-association"])(
    "leaves %s reachable to crawlers without a session",
    (path) => {
      expect(runsProxy(path)).toBe(false);
    },
  );

  it.each(["/_next/static/chunks/app.js", "/favicon.ico", "/brand/ball-party-mark-dark.png", "/icon.svg"])(
    "still skips static asset %s",
    (path) => {
      expect(runsProxy(path)).toBe(false);
    },
  );

  it.each(["/", "/login", "/profile", "/settings", "/admin/posts", "/lobby/ABCD", "/prompts/123", "/prompts/123/opengraph-image"])(
    "still gates %s",
    (path) => {
      expect(runsProxy(path)).toBe(true);
    },
  );
});
