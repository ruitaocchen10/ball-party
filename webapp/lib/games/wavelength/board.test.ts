import { describe, expect, it } from "vitest";
import { boardFromState, dialPoint, dialPosition, scoreAt, scoringWedges, validateClue } from "./board";

const state = { match_id: "match", mode: "coop", preset: "short", round_count: 4, current_round: 1, phase: "fill", phase_deadline: null, server_now: "2026-01-01T00:00:00Z", team_scores: [0] };

describe("Wavelength board", () => {
  it("parses only a complete state projection", () => {
    expect(boardFromState(state)).toMatchObject({ matchId: "match", phase: "fill" });
    expect(boardFromState({ ...state, team_scores: null })).toBeNull();
    expect(boardFromState({ ...state, phase: "unknown" })).toBeNull();
  });

  it("validates clues before the server rejects them", () => {
    expect(validateClue("  ")).toMatch(/Write/);
    expect(validateClue("Top 10")).toMatch(/digits/i);
    expect(validateClue("word ".repeat(9))).toMatch(/8 words/);
    expect(validateClue("x".repeat(101))).toMatch(/100 characters/);
    expect(validateClue("Great comeback story")).toBeNull();
  });

  it("builds the five scoring bands and scores their boundaries", () => {
    expect(scoringWedges(500)).toEqual([
      { points: 2, from: 400, to: 440 }, { points: 3, from: 440, to: 480 },
      { points: 4, from: 480, to: 520 }, { points: 3, from: 520, to: 560 }, { points: 2, from: 560, to: 600 },
    ]);
    expect(scoreAt(500, 500)).toBe(4);
    expect(scoreAt(540, 500)).toBe(3);
    expect(scoreAt(600, 500)).toBe(2);
    expect(scoreAt(601, 500)).toBe(0);
  });

  it("maps scale positions onto the dial semicircle and back", () => {
    expect(dialPoint(0).x).toBeCloseTo(30);
    expect(dialPoint(1000).x).toBeCloseTo(970);
    expect(dialPoint(500).y).toBeCloseTo(260 - 470);
    for (const position of [0, 125, 500, 876, 1000]) {
      const { x, y } = dialPoint(position);
      expect(dialPosition(x, y)).toBe(position);
    }
    expect(dialPosition(-50, 400)).toBe(0); // a pointer below/left of the arc clamps to the end
  });
});
