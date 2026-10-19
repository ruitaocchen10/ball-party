import { describe, expect, it } from "vitest";

import { ANALYTICS_OPT_OUT_COOKIE, hasOptOutCookie, optOutCookieString } from "@/lib/foundation/analytics/consent";

describe("analytics opt-out cookie", () => {
  it("finds the opt-out among other cookies", () => {
    expect(hasOptOutCookie(`a=b; ${ANALYTICS_OPT_OUT_COOKIE}=1; c=d`)).toBe(true);
    expect(hasOptOutCookie(`${ANALYTICS_OPT_OUT_COOKIE}=1`)).toBe(true);
  });

  it("is not fooled by a cleared cookie or a lookalike name", () => {
    expect(hasOptOutCookie("")).toBe(false);
    expect(hasOptOutCookie(`${ANALYTICS_OPT_OUT_COOKIE}=`)).toBe(false);
    expect(hasOptOutCookie(`x${ANALYTICS_OPT_OUT_COOKIE}=1`)).toBe(false);
  });

  it("writes a long-lived cookie to opt out and expires it to opt back in", () => {
    expect(optOutCookieString(true)).toMatch(/^bp_analytics_optout=1; Max-Age=\d{7,}; Path=\//);
    expect(optOutCookieString(false)).toMatch(/Max-Age=0/);
  });
});
