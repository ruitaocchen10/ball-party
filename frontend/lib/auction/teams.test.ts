import { describe, expect, it } from "vitest";

import { auctionLogoCode } from "@/lib/auction/teams";

describe("auctionLogoCode", () => {
  it("maps broadcast abbreviations to the shared logo bucket's franchise codes", () => {
    expect(auctionLogoCode("KC")).toBe("kan");
    expect(auctionLogoCode("NO")).toBe("nor");
    expect(auctionLogoCode("SF")).toBe("sfo");
  });

  it("keeps historical auction labels on their franchise's logo", () => {
    expect(auctionLogoCode("STL")).toBe("ram");
    expect(auctionLogoCode("SD")).toBe("sdg");
    expect(auctionLogoCode("OAK")).toBe("rai");
  });

  it("falls back to text for an unknown code", () => {
    expect(auctionLogoCode("XXX")).toBeNull();
  });
});
