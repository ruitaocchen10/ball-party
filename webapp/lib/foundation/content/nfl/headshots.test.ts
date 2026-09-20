import { describe, expect, it } from "vitest";

import { resizedHeadshotUrl } from "./headshots";

describe("resizedHeadshotUrl", () => {
  it("asks the CDN for a resized PNG on both path forms nflverse uses", () => {
    expect(resizedHeadshotUrl("https://static.www.nfl.com/image/upload/f_auto,q_auto/league/abc", 600))
      .toBe("https://static.www.nfl.com/image/upload/f_png,q_auto,w_600/league/abc");
    expect(resizedHeadshotUrl("https://static.www.nfl.com/image/private/f_auto,q_auto/league/abc", 900))
      .toBe("https://static.www.nfl.com/image/private/f_png,q_auto,w_900/league/abc");
  });

  it("leaves a URL it doesn't recognise alone", () => {
    expect(resizedHeadshotUrl("https://example.com/qb.jpg", 600)).toBe("https://example.com/qb.jpg");
    expect(resizedHeadshotUrl("", 600)).toBe("");
  });
});
