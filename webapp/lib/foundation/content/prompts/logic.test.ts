import { describe, expect, it } from "vitest";

import { coverOptions, needsCoverChoice } from "./logic";
import type { Option } from "./types";

const pool = (count: number, placed: Record<number, number> = {}): Option[] =>
  Array.from({ length: count }, (_, index) => ({ id: `p${index + 1}`, label: `Player ${index + 1}`, ...(placed[index + 1] ? { coverPosition: placed[index + 1] } : {}) }));

describe("coverOptions", () => {
  it("shows a small pool whole, in its own order", () => {
    expect(coverOptions(pool(3)).map((option) => option.id)).toEqual(["p1", "p2", "p3"]);
  });

  it("shows the first four of a bigger pool nobody has chosen from", () => {
    expect(coverOptions(pool(6)).map((option) => option.id)).toEqual(["p1", "p2", "p3", "p4"]);
  });

  it("shows the admin's four in the order they placed them, wherever they sit in the pool", () => {
    const options = pool(6, { 5: 1, 2: 2, 6: 3, 1: 4 });
    expect(coverOptions(options).map((option) => option.id)).toEqual(["p5", "p2", "p6", "p1"]);
  });

  it("doesn't reorder the pool it was given", () => {
    const options = pool(6, { 5: 1, 2: 2, 6: 3, 1: 4 });
    coverOptions(options);
    expect(options.map((option) => option.id)).toEqual(["p1", "p2", "p3", "p4", "p5", "p6"]);
  });
});

describe("needsCoverChoice", () => {
  it("is never needed for a pool the art can show whole", () => {
    expect(needsCoverChoice(pool(2))).toBe(false);
    expect(needsCoverChoice(pool(4))).toBe(false);
  });

  it("is needed until exactly four of a bigger pool are placed", () => {
    expect(needsCoverChoice(pool(5))).toBe(true);
    expect(needsCoverChoice(pool(5, { 1: 1, 2: 2, 3: 3 }))).toBe(true);
    expect(needsCoverChoice(pool(5, { 1: 1, 2: 2, 3: 3, 5: 4 }))).toBe(false);
  });
});
