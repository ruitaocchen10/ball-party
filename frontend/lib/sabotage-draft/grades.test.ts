import { describe, expect, it } from "vitest";

import { gradeForPick, gradeForTeam } from "./grades";

describe("gradeForPick", () => {
  it("grades a QB against QBs, not the shared scale", () => {
    // 18 AV clears a QB's own A- cutoff, well below their own ceiling
    // (best-ever QB season in the pool is 24). The same 18 AV is already
    // an ST's own top cutoff -- their best-ever season is only 8.
    expect(gradeForPick("QB", 18)).toBe("A-");
    expect(gradeForPick("ST", 18)).toBe("A+");
  });

  it("gives an elite special-teamer their own grade, not a QB-scale one", () => {
    // The whole point of position-relative grading: 4 AV is a rough season
    // for a QB (still below their own D- floor) but is comfortably a B+
    // for a special teamer.
    expect(gradeForPick("QB", 4)).toBe("D-");
    expect(gradeForPick("ST", 4)).toBe("B+");
  });

  it("folds RB1/RB2 and WR1/WR2/WR3 onto their shared category", () => {
    expect(gradeForPick("RB1", 9)).toBe(gradeForPick("RB2", 9));
    expect(gradeForPick("WR1", 9)).toBe(gradeForPick("WR3", 9));
  });

  it("bottoms out at a plain F for a replacement-level or negative season", () => {
    // F stays a single band on purpose, no F-/F+ -- nobody needs finer
    // resolution below replacement level.
    expect(gradeForPick("QB", -3)).toBe("F");
    expect(gradeForPick("QB", -1)).toBe("F");
  });

  it("distinguishes +/- within a letter, not just the letter itself", () => {
    // QB cutoffs: [..., 15, 16, 17, 18] for B-/B/B+/A- -- four different
    // grades sit in a narrow four-AV band below the top of the scale.
    expect(gradeForPick("QB", 13)).toBe("C+");
    expect(gradeForPick("QB", 15)).toBe("B-");
    expect(gradeForPick("QB", 16)).toBe("B");
    expect(gradeForPick("QB", 17)).toBe("B+");
    expect(gradeForPick("QB", 20)).toBe("A+");
  });
});

describe("gradeForTeam", () => {
  it("grades a roster against the fixed real-world baseline, not a curve", () => {
    expect(gradeForTeam(93)).toBe("C");
    expect(gradeForTeam(55)).toBe("F");
  });

  it("makes a genuinely strong roster earn its grade, not max the scale on a good draft", () => {
    // The best roster ever actually drafted in this game so far (126 AV,
    // 10-7 record) is a real A-caliber draft -- but the scale is now wide
    // enough that it grades A-, with room left above it, rather than
    // topping out the ladder the way a merely solid draft used to.
    expect(gradeForTeam(126)).toBe("A-");
  });

  it("distinguishes +/- within a letter", () => {
    expect(gradeForTeam(120)).toBe("B+");
    expect(gradeForTeam(130)).toBe("A");
    expect(gradeForTeam(136)).toBe("A+");
  });
});
