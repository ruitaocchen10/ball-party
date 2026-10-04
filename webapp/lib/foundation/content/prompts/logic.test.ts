import { describe, expect, it } from "vitest";

import { coverOptions, isPromptOpenForAnswers, matchesSearchQuery, needsCoverChoice, scoreSlot } from "./logic";
import type { Option, Slot } from "./types";

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

describe("isPromptOpenForAnswers", () => {
  const lockAt = "2026-09-20T12:00:00.000Z";
  const deadline = new Date(lockAt).getTime();

  it("accepts an open prompt only before its deadline", () => {
    expect(isPromptOpenForAnswers({ status: "open", lockAt }, deadline - 1)).toBe(true);
    expect(isPromptOpenForAnswers({ status: "open", lockAt }, deadline)).toBe(false);
    expect(isPromptOpenForAnswers({ status: "open", lockAt }, deadline + 1)).toBe(false);
  });

  it("never offers a closed lifecycle state or malformed deadline", () => {
    expect(isPromptOpenForAnswers({ status: "locked", lockAt }, deadline - 1)).toBe(false);
    expect(isPromptOpenForAnswers({ status: "resolved", lockAt }, deadline - 1)).toBe(false);
    expect(isPromptOpenForAnswers({ status: "open", lockAt: "not-a-date" }, deadline - 1)).toBe(false);
  });
});

describe("matchesSearchQuery", () => {
  const post = { promptText: "Who wins Jets vs Bills?", caption: "Week 4 lock", author: "cam" };

  it("matches everything for a blank or whitespace-only query", () => {
    expect(matchesSearchQuery(post, "")).toBe(true);
    expect(matchesSearchQuery(post, "   ")).toBe(true);
  });

  it("matches a substring anywhere in prompt text, caption, or author, case-insensitively", () => {
    expect(matchesSearchQuery(post, "jets")).toBe(true);
    expect(matchesSearchQuery(post, "WEEK 4")).toBe(true);
    expect(matchesSearchQuery(post, "Cam")).toBe(true);
  });

  it("rejects a query none of the three fields contain", () => {
    expect(matchesSearchQuery(post, "eagles")).toBe(false);
  });
});

describe("scoreSlot", () => {
  const slot: Slot = {
    id: "s",
    label: "Game",
    shape: "pick",
    points: 20,
    options: [
      { id: "kc-under_7", label: "Chiefs by <7", teamCode: "KC", margin: "under_7" },
      { id: "kc-7_plus", label: "Chiefs by 7+", teamCode: "KC", margin: "7_plus" },
      { id: "buf-under_7", label: "Bills by <7", teamCode: "BUF", margin: "under_7" },
      { id: "buf-7_plus", label: "Bills by 7+", teamCode: "BUF", margin: "7_plus" },
    ],
  };

  it("pays a four-option game pick all-or-nothing", () => {
    expect(scoreSlot({ ...slot, correct: ["buf-7_plus"] }, ["buf-7_plus"])?.pointsEarned).toBe(20);
    expect(scoreSlot({ ...slot, correct: ["buf-7_plus"] }, ["buf-under_7"])?.pointsEarned).toBe(0);
    expect(scoreSlot({ ...slot, correct: ["buf-7_plus"] }, ["kc-7_plus"])?.pointsEarned).toBe(0);
  });

  it("scores nothing for a no-contest slot (empty answer) or an ungraded one", () => {
    expect(scoreSlot({ ...slot, correct: [] }, ["buf-7_plus"])).toBeNull();
    expect(scoreSlot(slot, ["buf-7_plus"])).toBeNull();
  });
});

describe("isSlotNoContest", () => {
  it("is true only for a graded slot whose answer is empty", async () => {
    const { isSlotNoContest } = await import("@/lib/foundation/content/prompts/logic");
    expect(isSlotNoContest({ correct: [] })).toBe(true);
    expect(isSlotNoContest({ correct: undefined })).toBe(false);
    expect(isSlotNoContest({ correct: ["a"] })).toBe(false);
  });
});
