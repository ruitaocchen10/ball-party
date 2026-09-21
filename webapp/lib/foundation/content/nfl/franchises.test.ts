import { describe, expect, it } from "vitest";

import { FRANCHISE_NAMES, franchiseName } from "./franchises";
import { franchiseLogoUrl } from "./team-logos";

describe("franchise names", () => {
  it("covers exactly the pool's thirty-two franchises", () => {
    expect(Object.keys(FRANCHISE_NAMES)).toHaveLength(32);
  });

  it("names the codes that don't read as their modern team on sight", () => {
    expect(franchiseName("clt")).toBe("Indianapolis Colts");
    expect(franchiseName("crd")).toBe("Arizona Cardinals");
    expect(franchiseName("htx")).toBe("Houston Texans");
    expect(franchiseName("oti")).toBe("Tennessee Titans");
    expect(franchiseName("rav")).toBe("Baltimore Ravens");
    expect(franchiseName("sdg")).toBe("Los Angeles Chargers");
  });

  it("falls back to the raw code for anything unmapped, rather than dropping it", () => {
    expect(franchiseName("xyz")).toBe("xyz");
  });
});

describe("franchise logo urls", () => {
  it("points at the code's file in the public team-logos bucket", () => {
    const url = franchiseLogoUrl("oti");
    expect(url).toContain("/storage/v1/object/public/team-logos/oti.png");
  });
});
