import { act, render, screen, within } from "@testing-library/react";
import userEvent from "@testing-library/user-event";
import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";

import { QbSeasonBuilderResult } from "@/components/games/qb-season-builder/QbSeasonBuilderResult";
import { boardFromRow, type BoardRow, type ShownSpin } from "@/lib/games/qb-season-builder/board";
import { REVEAL_STEP_MS } from "@/lib/games/qb-season-builder/useSeasonReveal";
import { resultFromJson, type SeasonResult } from "@/lib/games/qb-season-builder/result";

/**
 * The staged reveal and the read-only result page — one component, two uses.
 *
 * jsdom on purpose: what is asserted is behaviour the screen decides — which
 * stage is up, what skipping does, what a reload does, what each kind of viewer
 * is shown. How it looks is out of reach here and is not faked with class
 * assertions. The numbers are the API's blended values, passed in as fixtures;
 * nothing here knows how a season is generated.
 *
 * That no source rating ever reaches a client is the API's half, asserted in
 * supabase/tests/0127_qb_season_builder_finish.test.sql; the screen's half is
 * only that it says nothing about where a rating came from.
 */

const MATCH = "22222222-2222-2222-2222-222222222222";

const PEYTON = { player_id: "00-0010346", display_name: "Peyton Manning" };
const MAHOMES = { player_id: "00-0033873", display_name: "Patrick Mahomes" };
const BRADY = { player_id: "00-0019596", display_name: "Tom Brady" };

/** A saved result, as `qb_season_builder.result` returns it. */
function resultRow(over: Record<string, unknown> = {}) {
  return {
    match_id: MATCH,
    mode: "visible",
    stat_line: {
      attempts: 598, completions: 412, pass_yards: 5104, pass_tds: 44, interceptions: 9,
      rating: 108.3, rush_yards: 312, rush_tds: 4,
    },
    record: { wins: 13, losses: 4 },
    playoffs: { depth: 4, result: "lost_super_bowl" },
    awards: { mvp: true, opoy: false, all_pro: true, pro_bowl: true, sb_mvp: false },
    score: 88.4,
    breakdown: [
      { component: "stat_line", weight: 50, percentile: 0.9, points: 45 },
      { component: "team_success", weight: 30, percentile: 0.8, points: 24 },
      { component: "awards", weight: 20, percentile: 0.97, points: 19.4 },
    ],
    picks: [
      { round: 1, slot: "accuracy", franchise_code: "den", season: 2013, ...PEYTON, value: 91 },
      { round: 2, slot: "arm_talent", franchise_code: "kan", season: 2018, ...MAHOMES, value: 97 },
      { round: 3, slot: "mobility", franchise_code: "nwe", season: 2007, ...BRADY, value: 41 },
      { round: 4, slot: "iq", franchise_code: "den", season: 2013, ...PEYTON, value: 96 },
      { round: 5, slot: "build", franchise_code: "kan", season: 2018, ...MAHOMES, value: 84 },
      { round: 6, slot: "supporting_cast", franchise_code: "nwe", season: 2007, player_id: null, display_name: null, value: 93 },
    ],
    ...over,
  };
}

function resultOf(over: Record<string, unknown> = {}): SeasonResult {
  const parsed = resultFromJson(resultRow(over));
  if (!parsed) throw new Error("the fixture is not a result");
  return parsed;
}

/** The five qualities of a quarterback, revealed. */
const qualities = (seed: number) => ({
  accuracy: seed + 1, arm_talent: seed + 2, mobility: seed + 3, iq: seed + 4, build: seed + 5,
});

/**
 * The reveal a hidden run gets back in `state`: every spin the player saw, the
 * ones passed on and a respun-away spin included.
 */
function shownOf(): ShownSpin[] {
  const row: BoardRow = {
    match_id: MATCH, mode: "hidden", phase: "complete", round_count: 6, current_round: 6,
    respin_used: true, franchise_code: null, season: null, options: null, picks: [],
    shown: [
      // Round 1's first spin, thrown away by the respin.
      {
        round: 1, attempt: 1, franchise_code: "sea", season: 2010,
        options: { quarterbacks: [{ player_id: "00-0000001", display_name: "Matt Hasselbeck", values: qualities(50) }], supporting_cast: { value: 55 } },
      },
      // Round 1 as dealt after the respin: Peyton's accuracy was taken, his arm passed on.
      {
        round: 1, attempt: 2, franchise_code: "den", season: 2013,
        options: { quarterbacks: [{ ...PEYTON, values: qualities(80) }], supporting_cast: { value: 71 } },
      },
      {
        round: 6, attempt: 1, franchise_code: "nwe", season: 2007,
        options: { quarterbacks: [{ ...BRADY, values: qualities(60) }], supporting_cast: { value: 93 } },
      },
    ],
  };
  const board = boardFromRow(row);
  if (!board?.shown) throw new Error("the fixture is not a reveal");
  return board.shown;
}

type Props = Partial<Parameters<typeof QbSeasonBuilderResult>[0]>;

function renderResult(props: Props = {}) {
  return render(
    <QbSeasonBuilderResult
      result={resultOf()}
      shown={null}
      personalBest={null}
      isGuest={false}
      staged={false}
      {...props}
    />,
  );
}

const stages = () => screen.queryAllByRole("region").map((region) => region.getAttribute("aria-label"));

beforeEach(() => localStorage.clear());

describe("QbSeasonBuilderResult — the staged reveal", () => {
  beforeEach(() => vi.useFakeTimers({ toFake: ["setTimeout", "clearTimeout"] }));
  afterEach(() => {
    vi.useRealTimers();
    vi.restoreAllMocks();
  });

  const step = () => act(() => vi.advanceTimersByTime(REVEAL_STEP_MS));

  it("plays stat line, record, playoffs, awards, then the score, one step at a time", () => {
    renderResult({ staged: true });

    expect(stages()).toEqual(["Stat line"]);
    step();
    expect(stages()).toEqual(["Stat line", "Record"]);
    step();
    expect(stages()).toEqual(["Stat line", "Record", "Playoffs"]);
    step();
    expect(stages()).toEqual(["Stat line", "Record", "Playoffs", "Awards"]);
    expect(screen.queryByRole("region", { name: "Score" })).not.toBeInTheDocument();
    step();
    // The score is the payoff, so it lands on its own beat: what explains it
    // comes after.
    expect(stages()).toEqual(["Stat line", "Record", "Playoffs", "Awards", "Score"]);
    expect(screen.queryByRole("region", { name: /breakdown/i })).not.toBeInTheDocument();
    step();
    expect(stages()).toEqual([
      "Stat line", "Record", "Playoffs", "Awards", "Score", "Score breakdown", "Your six picks",
    ]);
  });

  it("shows what each stage says", () => {
    renderResult({ staged: true });
    step(); step(); step(); step(); step();

    expect(within(screen.getByRole("region", { name: "Stat line" })).getByText("5,104")).toBeInTheDocument();
    expect(within(screen.getByRole("region", { name: "Record" })).getByText("13–4")).toBeInTheDocument();
    expect(within(screen.getByRole("region", { name: "Playoffs" })).getByText("Lost the Super Bowl")).toBeInTheDocument();
    expect(within(screen.getByRole("region", { name: "Score" })).getByText("88.4")).toBeInTheDocument();
  });

  it("stops offering to skip once the reveal has played through", () => {
    renderResult({ staged: true });
    step(); step(); step(); step(); step();

    expect(screen.queryByRole("button", { name: /skip/i })).not.toBeInTheDocument();
  });

  it("does not replay after it has been watched through, when the page is reloaded", () => {
    const first = renderResult({ staged: true });
    step(); step(); step(); step(); step();
    first.unmount();

    renderResult({ staged: true });

    // Straight to the final state: no first stage waiting on a timer.
    expect(stages()).toContain("Your six picks");
    expect(screen.queryByRole("button", { name: /skip/i })).not.toBeInTheDocument();
  });

  it("starts over from the stat line when reloaded before it was watched through", () => {
    const first = renderResult({ staged: true });
    step(); step();
    first.unmount();

    renderResult({ staged: true });

    expect(stages()).toEqual(["Stat line"]);
  });

  it("remembers one run's reveal without spoiling another's", () => {
    const first = renderResult({ staged: true });
    step(); step(); step(); step(); step();
    first.unmount();

    renderResult({ staged: true, result: resultOf({ match_id: "33333333-3333-3333-3333-333333333333" }) });

    expect(stages()).toEqual(["Stat line"]);
  });

  it("plays again rather than failing when the browser will not remember", () => {
    vi.spyOn(Storage.prototype, "setItem").mockImplementation(() => { throw new Error("blocked"); });
    vi.spyOn(Storage.prototype, "getItem").mockImplementation(() => { throw new Error("blocked"); });
    const first = renderResult({ staged: true });
    step(); step(); step(); step(); step();
    expect(stages()).toContain("Your six picks");
    first.unmount();

    renderResult({ staged: true });

    expect(stages()).toEqual(["Stat line"]);
  });
});

describe("QbSeasonBuilderResult — skipping", () => {
  it("can be skipped straight to the final state", async () => {
    const user = userEvent.setup();
    renderResult({ staged: true });

    await user.click(screen.getByRole("button", { name: /skip/i }));

    expect(stages()).toEqual([
      "Stat line", "Record", "Playoffs", "Awards", "Score", "Score breakdown", "Your six picks",
    ]);
    // Nothing left to skip.
    expect(screen.queryByRole("button", { name: /skip/i })).not.toBeInTheDocument();
  });

  it("does not replay after it has been skipped, when the page is reloaded", async () => {
    const user = userEvent.setup();
    const first = renderResult({ staged: true });
    await user.click(screen.getByRole("button", { name: /skip/i }));
    first.unmount();

    renderResult({ staged: true });

    expect(stages()).toContain("Your six picks");
  });
});

describe("QbSeasonBuilderResult — awards", () => {
  it("lists the awards the season won, and only those", () => {
    renderResult();

    const awards = within(screen.getByRole("region", { name: "Awards" }));
    expect(awards.getByText("MVP")).toBeInTheDocument();
    expect(awards.getByText("First-Team All-Pro")).toBeInTheDocument();
    expect(awards.getByText("Pro Bowl")).toBeInTheDocument();
    expect(awards.queryByText("Offensive Player of the Year")).not.toBeInTheDocument();
    expect(awards.queryByText("Super Bowl MVP")).not.toBeInTheDocument();
  });

  it("says so when the season won nothing", () => {
    renderResult({
      result: resultOf({ awards: { mvp: false, opoy: false, all_pro: false, pro_bowl: false, sb_mvp: false } }),
    });

    expect(within(screen.getByRole("region", { name: "Awards" })).getByText(/no awards/i)).toBeInTheDocument();
  });
});

describe("QbSeasonBuilderResult — the final state", () => {
  it("breaks the score down by what drove it", () => {
    renderResult();

    const breakdown = within(screen.getByRole("region", { name: "Score breakdown" }));
    for (const [name, points] of [["Stat line", "45"], ["Team success", "24"], ["Awards", "19.4"]]) {
      expect(within(breakdown.getByText(name).closest("li")!).getByText(new RegExp(`\\b${points}\\b`))).toBeInTheDocument();
    }
    // How the score reads against real seasons.
    expect(breakdown.getByText(/better than 90% of real seasons/i)).toBeInTheDocument();
  });

  it("recaps which real season each of the six values came from", () => {
    renderResult();

    const picks = within(screen.getByRole("list", { name: "Your six picks" })).getAllByRole("listitem");
    expect(picks).toHaveLength(6);
    expect(picks[0]).toHaveTextContent(/accuracy/i);
    expect(picks[0]).toHaveTextContent("Peyton Manning");
    expect(picks[0]).toHaveTextContent("2013 Denver Broncos");
    expect(picks[0]).toHaveTextContent("91");
    // The Supporting Cast comes from a team, not a quarterback.
    expect(picks[5]).toHaveTextContent(/supporting cast/i);
    expect(picks[5]).toHaveTextContent("New England Patriots");
    expect(picks[5]).toHaveTextContent("93");
  });

  it("never says where the ratings came from", () => {
    const { container } = renderResult({ shown: shownOf(), result: resultOf({ mode: "hidden" }) });

    expect(container).not.toHaveTextContent(/madden|ea sports/i);
  });
});

describe("QbSeasonBuilderResult — hidden mode", () => {
  it("reveals the values of every option seen, including the ones passed on", () => {
    renderResult({ result: resultOf({ mode: "hidden" }), shown: shownOf() });

    const seen = within(screen.getByRole("region", { name: "Every option you saw" }));
    // Peyton's arm talent was on the spin and passed on: 80 + 2.
    const peyton = within(seen.getByRole("group", { name: /peyton manning/i }));
    expect(peyton.getByText("Arm Talent").closest("li")).toHaveTextContent("82");
    expect(peyton.getByText("Mobility").closest("li")).toHaveTextContent("83");
    // The team's cast on that spin, taken by nobody.
    const spin = within(seen.getByText("Round 1 · 2013 Denver Broncos").closest("li")!);
    expect(spin.getByText("Supporting Cast").closest("li")).toHaveTextContent("71");
  });

  it("includes a spin the respin threw away, and says so", () => {
    renderResult({ result: resultOf({ mode: "hidden" }), shown: shownOf() });

    const seen = within(screen.getByRole("region", { name: "Every option you saw" }));
    expect(seen.getByText(/2010 Seattle Seahawks/)).toBeInTheDocument();
    expect(seen.getByRole("group", { name: /matt hasselbeck/i })).toBeInTheDocument();
    expect(seen.getAllByText(/respun/i)).toHaveLength(1);
  });

  it("marks the options that were taken", () => {
    renderResult({ result: resultOf({ mode: "hidden" }), shown: shownOf() });

    const seen = within(screen.getByRole("region", { name: "Every option you saw" }));
    const peyton = within(seen.getByRole("group", { name: /peyton manning/i }));
    expect(peyton.getByText("Accuracy").closest("li")).toHaveTextContent(/taken/i);
    expect(peyton.getByText("Arm Talent").closest("li")).not.toHaveTextContent(/taken/i);
  });

  it("is not shown for a visible run, whose values were on screen all along", () => {
    renderResult({ result: resultOf({ mode: "visible" }), shown: shownOf() });

    expect(screen.queryByRole("region", { name: "Every option you saw" })).not.toBeInTheDocument();
  });

  it("is not shown where the passed-on options are not known, as on a public result", () => {
    renderResult({ result: resultOf({ mode: "hidden" }), shown: null });

    expect(screen.queryByRole("region", { name: "Every option you saw" })).not.toBeInTheDocument();
    // The season itself is all there.
    expect(screen.getByRole("region", { name: "Score" })).toBeInTheDocument();
  });

  it("says which mode the run was in", () => {
    renderResult({ result: resultOf({ mode: "hidden" }) });

    expect(screen.getByText(/ratings hidden/i)).toBeInTheDocument();
  });
});

describe("QbSeasonBuilderResult — read-only", () => {
  it("renders the whole result at once, with nothing to skip, for someone who did not play it", () => {
    renderResult({ staged: false });

    expect(stages()).toEqual([
      "Stat line", "Record", "Playoffs", "Awards", "Score", "Score breakdown", "Your six picks",
    ]);
    expect(screen.queryByRole("button")).not.toBeInTheDocument();
  });

  it("offers a way in to play their own", () => {
    renderResult({ staged: false });

    expect(screen.getByRole("link", { name: /build your own/i })).toHaveAttribute("href", "/solo");
  });

  it("points the player at the read-only page they can share, once the season is out", async () => {
    const user = userEvent.setup();
    renderResult({ staged: true });
    // Not before: the link would give the season away.
    expect(screen.queryByRole("link", { name: /shareable result/i })).not.toBeInTheDocument();
    await user.click(screen.getByRole("button", { name: /skip/i }));

    expect(screen.getByRole("link", { name: /shareable result/i })).toHaveAttribute(
      "href",
      `/solo/qb-season-builder/result/${MATCH}`,
    );
  });
});

describe("QbSeasonBuilderResult — who is looking", () => {
  it("shows a signed-in player their personal best for the run's mode", () => {
    renderResult({ result: resultOf({ mode: "hidden" }), personalBest: 91.5 });

    expect(screen.getByText(/personal best/i)).toHaveTextContent(/hidden/i);
    expect(screen.getByText(/personal best/i)).toHaveTextContent("91.5");
  });

  it("shows no personal best to someone who has none", () => {
    renderResult({ personalBest: null });

    expect(screen.queryByText(/personal best/i)).not.toBeInTheDocument();
  });

  it("nudges a guest to make an account, and shows them no personal best", () => {
    renderResult({ isGuest: true, personalBest: 91.5 });

    expect(screen.getByText(/keep your runs/i)).toBeInTheDocument();
    expect(screen.getByRole("link", { name: /create an account/i })).toHaveAttribute("href", "/settings");
    expect(screen.queryByText(/personal best/i)).not.toBeInTheDocument();
  });

  it("does not nudge a signed-in player", () => {
    renderResult({ isGuest: false, personalBest: 70 });

    expect(screen.queryByText(/keep your runs/i)).not.toBeInTheDocument();
    expect(screen.queryByRole("link", { name: /create an account/i })).not.toBeInTheDocument();
  });
});
