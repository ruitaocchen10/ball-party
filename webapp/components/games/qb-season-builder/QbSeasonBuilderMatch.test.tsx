import { act, render, screen, within } from "@testing-library/react";
import userEvent from "@testing-library/user-event";
import { describe, expect, it, vi } from "vitest";

const refresh = vi.fn();
const timedReveal = vi.hoisted(() => ({ revealed: true }));

vi.mock("next/navigation", () => ({
  useRouter: () => ({ refresh }),
}));

vi.mock("@/lib/foundation/ui-kit/useTimedReveal", () => ({
  useTimedReveal: () => ({ revealed: timedReveal.revealed }),
}));

// The screen never imports `playSolo` itself — a game may not import
// platform directly (docs/architecture/architecture.md) — so the page hands
// it down as `startNewSeason`. A plain fn stands in for it here.
const playSolo = vi.fn();

import { QbSeasonBuilderMatch } from "@/components/games/qb-season-builder/QbSeasonBuilderMatch";
import { boardFromRow, type Board, type BoardRow } from "@/lib/games/qb-season-builder/board";
import { supabaseMock } from "@/test/factories";

/**
 * The pick screen, on a run in play.
 *
 * jsdom on purpose: everything asserted here is behaviour the screen decides —
 * which spin is up, which slots are open, which controls can be used, which
 * number is on screen. How it looks is out of reach here and is not faked with
 * class assertions.
 *
 * The hiding of a hidden run's numbers is asserted twice over, because a screen
 * is the weakest half of it: the number is absent from the DOM, not merely
 * styled out of the way. The server-side half — that the API never returned it
 * at all — is supabase/tests/0122_qb_season_builder_modes_and_leaks.test.sql.
 */

const MATCH = "22222222-2222-2222-2222-222222222222";

const PEYTON = { player_id: "00-0010346", display_name: "Peyton Manning", headshot_url: "https://example.test/peyton.png" };
const BRADY = { player_id: "00-0019596", display_name: "Tom Brady" };

/** The five qualities of a quarterback, or null the way a hidden run sends them. */
function values(seed: number, revealed: boolean) {
  return revealed
    ? { accuracy: seed + 1, arm_talent: seed + 2, mobility: seed + 3, iq: seed + 4, build: seed + 5 }
    : null;
}

/**
 * A `board` row the way `qb_season_builder.state` returns it: a run in round 1,
 * on Denver 2013 with one quarterback, nothing picked yet.
 */
function row(over: Partial<BoardRow> & { revealed?: boolean } = {}): BoardRow {
  const { revealed = true, ...rest } = over;
  return {
    match_id: MATCH,
    mode: revealed ? "visible" : "hidden",
    era: "all",
    phase: "picking",
    round_count: 6,
    current_round: 1,
    respin_used: false,
    franchise_code: "den",
    season: 2013,
    options: {
      quarterbacks: [{ ...PEYTON, values: values(80, revealed) }],
      supporting_cast: { value: revealed ? 71 : null },
    },
    picks: [],
    shown: null,
    ...rest,
  };
}

function boardOf(over: Parameters<typeof row>[0] = {}): Board {
  const parsed = boardFromRow(row(over));
  if (!parsed) throw new Error("the fixture row is not a board");
  return parsed;
}

/** `before` runs ahead of the first render, for a screen that calls the server on mount. */
function renderScreen(
  initial: Board,
  { isGuest = false, before }: { isGuest?: boolean; before?: (supabase: ReturnType<typeof supabaseMock>) => void } = {},
) {
  const supabase = supabaseMock();
  globalThis.__supabaseMock = supabase;
  before?.(supabase);
  const view = render(<QbSeasonBuilderMatch matchId={MATCH} initial={initial} isGuest={isGuest} startNewSeason={playSolo} />);
  return { ...view, supabase };
}

/** Makes the next `pick` / `respin` / `state` calls answer as the server would. */
function answer(
  supabase: ReturnType<typeof supabaseMock>,
  replies: Partial<Record<"pick" | "respin" | "state", BoardRow | { message: string }>>,
) {
  supabase.rpc.mockImplementation(async (fn: unknown) => {
    const reply = replies[fn as "pick" | "respin" | "state"];
    if (!reply) return { data: null, error: null };
    return "message" in reply && !("match_id" in reply)
      ? { data: null, error: reply }
      : { data: reply, error: null };
  });
}

const MAHOMES = { player_id: "00-0033873", display_name: "Patrick Mahomes" };

/** Round 2 after Peyton's accuracy was taken, dealt Kansas City 2018. */
function roundTwo(over: Partial<BoardRow> = {}): BoardRow {
  return row({
    current_round: 2,
    franchise_code: "kan",
    season: 2018,
    options: {
      quarterbacks: [{ ...MAHOMES, values: values(90, true) }],
      supporting_cast: { value: 84 },
    },
    picks: [
      { round: 1, slot: "accuracy", franchise_code: "den", season: 2013, ...PEYTON, value: 81 },
    ],
    ...over,
  });
}

describe("QbSeasonBuilderMatch — picking", () => {
  it("shows a quarterback's portrait beside their name", () => {
    renderScreen(boardOf());

    expect(screen.getByRole("group", { name: "Peyton Manning" }).querySelector("img")).toHaveAttribute("src", PEYTON.headshot_url);
  });

  it("lets a quality of a quarterback be chosen, says which slot it fills, and locks it in through the game API", async () => {
    const user = userEvent.setup();
    const { supabase } = renderScreen(boardOf());
    answer(supabase, { pick: roundTwo() });

    const lockIn = screen.getByRole("button", { name: /lock in/i });
    expect(lockIn).toBeDisabled();

    await user.click(within(screen.getByRole("group", { name: "Peyton Manning" })).getByRole("radio", { name: /accuracy/i }));
    expect(screen.getByText(/taking accuracy from peyton manning/i)).toBeInTheDocument();
    expect(lockIn).toBeEnabled();

    await user.click(lockIn);

    expect(supabase.schema).toHaveBeenCalledWith("qb_season_builder");
    expect(supabase.rpc).toHaveBeenCalledWith("pick", {
      p_match_id: MATCH,
      p_slot: "accuracy",
      p_player_id: PEYTON.player_id,
    });
    // The server dealt round 2; the screen shows it and the filled slot.
    expect(await screen.findByText("Kansas City Chiefs")).toBeInTheDocument();
    expect(screen.getByText(/round 2 of 6/i)).toBeInTheDocument();
    const slots = within(screen.getByRole("list", { name: "Your build" })).getAllByRole("listitem");
    expect(within(slots[0]).getByText("Peyton Manning")).toBeInTheDocument();
    // A fresh spin starts with nothing chosen.
    expect(screen.getByRole("button", { name: /lock in/i })).toBeDisabled();
  });

  it("takes the Supporting Cast with no quarterback named", async () => {
    const user = userEvent.setup();
    const { supabase } = renderScreen(boardOf());
    answer(supabase, { pick: roundTwo({ picks: [{ round: 1, slot: "supporting_cast", franchise_code: "den", season: 2013, player_id: null, display_name: null, value: 71 }] }) });

    await user.click(screen.getByRole("radio", { name: /supporting cast/i }));
    expect(screen.getByText(/taking supporting cast/i)).toBeInTheDocument();
    await user.click(screen.getByRole("button", { name: /lock in/i }));

    expect(supabase.rpc).toHaveBeenCalledWith("pick", { p_match_id: MATCH, p_slot: "supporting_cast" });
  });

  it("does not offer a slot that is already filled, and says so rather than leaving it a plain disabled radio", () => {
    renderScreen(boardOf({
      current_round: 2,
      picks: [{ round: 1, slot: "accuracy", franchise_code: "kan", season: 2018, ...MAHOMES, value: 90 }],
    }));

    expect(screen.getByRole("radio", { name: /accuracy/i })).toBeDisabled();
    expect(screen.getByRole("radio", { name: /arm talent/i })).toBeEnabled();

    const accuracyRow = screen.getByRole("radio", { name: /accuracy/i }).closest("label")!;
    expect(within(accuracyRow).getByText(/already picked/i)).toBeInTheDocument();
    const armTalentRow = screen.getByRole("radio", { name: /arm talent/i }).closest("label")!;
    expect(within(armTalentRow).queryByText(/already picked/i)).not.toBeInTheDocument();
  });
});

describe("QbSeasonBuilderMatch — the respin", () => {
  it("keeps run controls in the sidebar, and starts a new season in one click, no confirmation", async () => {
    const user = userEvent.setup();
    renderScreen(boardOf());

    const controls = screen.getByRole("complementary", { name: /current run/i });
    expect(within(controls).getByRole("button", { name: /respin team/i })).toBeEnabled();
    await user.click(within(controls).getByRole("button", { name: /new season/i }));

    expect(playSolo).toHaveBeenCalledTimes(1);
    const [formData] = playSolo.mock.calls[0] as [FormData];
    expect(formData.get("game")).toBe("qb_season_builder");
    expect(formData.get("mode")).toBe("visible");
  });

  it("rerolls the whole spin through the game API and shows the respin as spent", async () => {
    const user = userEvent.setup();
    const { supabase } = renderScreen(boardOf());
    answer(supabase, { respin: row({ respin_used: true, franchise_code: "kan", season: 2018, options: { quarterbacks: [{ ...MAHOMES, values: values(90, true) }], supporting_cast: { value: 84 } } }) });

    const respin = screen.getByRole("button", { name: /respin/i });
    expect(respin).toBeEnabled();
    await user.click(respin);

    expect(supabase.rpc).toHaveBeenCalledWith("respin", { p_match_id: MATCH });
    expect(await screen.findByText("Kansas City Chiefs")).toBeInTheDocument();
    expect(screen.queryByText("Denver Broncos")).not.toBeInTheDocument();
    expect(screen.getByRole("button", { name: /respin used/i })).toBeDisabled();
  });

  it("shows a respin already spent, before anything is clicked", () => {
    renderScreen(boardOf({ respin_used: true }));

    expect(screen.getByRole("button", { name: /respin used/i })).toBeDisabled();
  });

  it("clears a chosen option when the spin it belonged to is thrown away", async () => {
    const user = userEvent.setup();
    const { supabase } = renderScreen(boardOf());
    answer(supabase, { respin: row({ respin_used: true, franchise_code: "kan", season: 2018, options: { quarterbacks: [{ ...MAHOMES, values: values(90, true) }], supporting_cast: { value: 84 } } }) });

    await user.click(screen.getByRole("radio", { name: /supporting cast/i }));
    await user.click(screen.getByRole("button", { name: /respin/i }));

    await screen.findByText("Kansas City Chiefs");
    expect(screen.getByRole("radio", { name: /supporting cast/i })).not.toBeChecked();
    expect(screen.getByRole("button", { name: /lock in/i })).toBeDisabled();
  });
});

describe("QbSeasonBuilderMatch — when the server refuses a move", () => {
  it("says so in plain words and re-reads the run, so a stale screen catches up", async () => {
    const user = userEvent.setup();
    const { supabase } = renderScreen(boardOf());
    // Another tab already took Accuracy; this one has not heard yet.
    answer(supabase, {
      pick: { message: "slot_filled" },
      state: roundTwo({ franchise_code: "den", season: 2013, options: row().options }),
    });

    await user.click(screen.getByRole("radio", { name: /accuracy/i }));
    await user.click(screen.getByRole("button", { name: /lock in/i }));

    expect(await screen.findByRole("alert")).toHaveTextContent("That slot is already filled.");
    expect(supabase.rpc).toHaveBeenCalledWith("state", { p_match_id: MATCH });
    expect(screen.getByRole("radio", { name: /accuracy/i })).toBeDisabled();
    expect(screen.getByText(/round 2 of 6/i)).toBeInTheDocument();
  });

  it("keeps every control off until the re-read is back, so a second click cannot race it", async () => {
    const user = userEvent.setup();
    const { supabase } = renderScreen(boardOf());
    let release: (reply: { data: BoardRow; error: null }) => void = () => {};
    supabase.rpc.mockImplementation(async (fn: unknown) => {
      if (fn === "state") return new Promise((resolve) => { release = resolve; });
      return { data: null, error: { message: "slot_filled" } };
    });

    await user.click(screen.getByRole("radio", { name: /accuracy/i }));
    await user.click(screen.getByRole("button", { name: /lock in/i }));

    // The refusal is on screen, but the run has not been re-read yet.
    expect(await screen.findByRole("alert")).toHaveTextContent("That slot is already filled.");
    expect(screen.getByRole("button", { name: /respin/i })).toBeDisabled();
    expect(screen.getByRole("button", { name: /lock in/i })).toBeDisabled();

    await act(async () => release({ data: roundTwo(), error: null }));
    expect(await screen.findByText(/round 2 of 6/i)).toBeInTheDocument();
    expect(screen.getByRole("button", { name: /respin/i })).toBeEnabled();
  });

  it("shows a message it has no wording for as the server sent it", async () => {
    const user = userEvent.setup();
    const { supabase } = renderScreen(boardOf());
    answer(supabase, { respin: { message: "something_new" } });

    await user.click(screen.getByRole("button", { name: /respin/i }));

    expect(await screen.findByRole("alert")).toHaveTextContent("something_new");
  });
});

describe("QbSeasonBuilderMatch — a guest", () => {
  it("is nudged to make an account to keep their runs", () => {
    renderScreen(boardOf(), { isGuest: true });

    expect(screen.getByText(/keep your runs/i)).toBeInTheDocument();
    expect(screen.getByRole("link", { name: /create an account/i })).toHaveAttribute("href", "/settings");
  });

  it("is not nudged when signed in to an account", () => {
    renderScreen(boardOf(), { isGuest: false });

    expect(screen.queryByText(/keep your runs/i)).not.toBeInTheDocument();
    expect(screen.queryByRole("link", { name: /create an account/i })).not.toBeInTheDocument();
  });
});

describe("QbSeasonBuilderMatch — all six slots filled", () => {
  const full = [
    ["accuracy", PEYTON, 81],
    ["arm_talent", MAHOMES, 92],
    ["mobility", BRADY, 60],
    ["iq", PEYTON, 84],
    ["build", MAHOMES, 95],
  ] as const;

  const fivePicks = full.map(([slot, who, value], index) => ({
    round: index + 1, slot, franchise_code: "den", season: 2013, ...who, value,
  }));

  function finished(phase: "ready_to_finish" | "complete") {
    return boardOf({
      phase,
      current_round: 6,
      franchise_code: null,
      season: null,
      options: null,
      picks: [
        ...fivePicks,
        { round: 6, slot: "supporting_cast", franchise_code: "nwe", season: 2007, player_id: null, display_name: null, value: 88 },
      ],
    });
  }

  /** The run's last round, one slot (Supporting Cast) still open. */
  function lastRound() {
    return boardOf({ current_round: 6, picks: [...fivePicks] });
  }

  /** Answers `pick` with the run's last slot filled and `finish` per `finishReply`. */
  function answerLastPick(supabase: ReturnType<typeof supabaseMock>, finishReply: { data: unknown; error: { message: string } | null }) {
    supabase.rpc.mockImplementation(async (fn: unknown) => {
      if (fn === "pick") return { data: row({ ...finishedRow() }), error: null };
      if (fn === "finish") return finishReply;
      return { data: null, error: null };
    });
  }

  function finishedRow(): Partial<BoardRow> {
    return {
      phase: "ready_to_finish",
      current_round: 6,
      franchise_code: null,
      season: null,
      options: null,
      picks: [
        ...fivePicks,
        { round: 6, slot: "supporting_cast", franchise_code: "nwe", season: 2007, player_id: null, display_name: null, value: 88 },
      ],
    };
  }

  it("goes straight to the reveal after the last pick, with no confirmation step", async () => {
    const user = userEvent.setup();
    const { supabase } = renderScreen(lastRound());
    answerLastPick(supabase, { data: null, error: null });

    await user.click(screen.getByRole("radio", { name: /supporting cast/i }));
    await user.click(screen.getByRole("button", { name: /lock in/i }));

    await vi.waitFor(() => expect(supabase.rpc).toHaveBeenCalledWith("finish", { p_match_id: MATCH }));
    expect(supabase.schema).toHaveBeenCalledWith("qb_season_builder");
    // The page is server-rendered from the run, which is now complete.
    await vi.waitFor(() => expect(refresh).toHaveBeenCalledTimes(1));
    expect(screen.queryByText(/all six slots are filled/i)).not.toBeInTheDocument();
    expect(screen.queryByRole("button", { name: /reveal my season/i })).not.toBeInTheDocument();
  });

  it("finishes a run that is opened with every slot already filled", async () => {
    const { supabase } = renderScreen(finished("ready_to_finish"));

    await vi.waitFor(() => expect(supabase.rpc).toHaveBeenCalledWith("finish", { p_match_id: MATCH }));
    expect(supabase.rpc.mock.calls.filter(([fn]) => fn === "finish")).toHaveLength(1);
    expect(screen.queryByRole("radio")).not.toBeInTheDocument();
    expect(screen.queryByRole("button", { name: /lock in|respin/i })).not.toBeInTheDocument();
  });

  it("shows progress, not a button, while the season is being generated", async () => {
    renderScreen(finished("ready_to_finish"), {
      before: (supabase) => supabase.rpc.mockImplementation(() => new Promise(() => {})),
    });

    expect(await screen.findByRole("status")).toHaveTextContent(/revealing your season/i);
    expect(screen.queryByRole("button", { name: /try again/i })).not.toBeInTheDocument();
  });

  it("says why when the season cannot be generated, and lets the player try again", async () => {
    const user = userEvent.setup();
    const { supabase } = renderScreen(finished("ready_to_finish"), {
      before: (mock) => mock.rpc.mockResolvedValue({ data: null, error: { message: "draft_incomplete" } }),
    });

    expect(await screen.findByRole("alert")).toHaveTextContent("Fill all six slots first.");
    expect(refresh).not.toHaveBeenCalled();

    supabase.rpc.mockResolvedValue({ data: null, error: null });
    await user.click(screen.getByRole("button", { name: /try again/i }));

    await vi.waitFor(() => expect(refresh).toHaveBeenCalledTimes(1));
  });

  it("goes to the reveal anyway when the run turns out to be finished already, as from another tab", async () => {
    renderScreen(finished("ready_to_finish"), {
      before: (supabase) => supabase.rpc.mockResolvedValue({ data: null, error: { message: "match_not_playing" } }),
    });

    await vi.waitFor(() => expect(refresh).toHaveBeenCalledTimes(1));
    expect(screen.queryByText(/already ended/i)).not.toBeInTheDocument();
  });

  it("has nothing to finish while slots are still open", () => {
    const { supabase } = renderScreen(boardOf());

    expect(supabase.rpc).not.toHaveBeenCalledWith("finish", expect.anything());
    expect(screen.queryByRole("button", { name: /reveal my season/i })).not.toBeInTheDocument();
  });

  it("opens a finished run read-only from its URL", () => {
    const { supabase } = renderScreen(finished("complete"));

    expect(supabase.rpc).not.toHaveBeenCalledWith("finish", expect.anything());
    expect(screen.queryByRole("radio")).not.toBeInTheDocument();
    expect(screen.getByText(/this run is finished/i)).toBeInTheDocument();
  });
});

describe("QbSeasonBuilderMatch — the spin", () => {
  it("keeps quarterback options hidden until the team spinner finishes, but keeps the build card up throughout", () => {
    timedReveal.revealed = false;
    const initial = boardOf();
    const { container, rerender } = renderScreen(initial);

    expect(container.querySelector(".animate-reel-spin")).toBeInTheDocument();
    expect(container.querySelector(".animate-reel-spin")).toHaveStyle({ animationDuration: "2000ms" });
    expect(screen.queryByRole("radio")).not.toBeInTheDocument();
    expect(screen.queryByRole("button", { name: /lock in/i })).not.toBeInTheDocument();
    // "Your build" never disappears while the team spins — only the player
    // cards wait on the reveal.
    expect(screen.getByRole("list", { name: "Your build" })).toBeInTheDocument();

    timedReveal.revealed = true;
    rerender(<QbSeasonBuilderMatch matchId={MATCH} initial={initial} isGuest={false} startNewSeason={playSolo} />);

    expect(screen.getByText("Denver Broncos")).toBeInTheDocument();
    expect(screen.getByRole("radio", { name: /accuracy/i })).toBeEnabled();
    expect(screen.getByRole("list", { name: "Your build" })).toBeInTheDocument();
  });

  it("shows the round, the spun team-season and its qualifying quarterbacks", async () => {
    renderScreen(boardOf({
      current_round: 2,
      options: {
        quarterbacks: [
          { ...PEYTON, values: values(80, true) },
          { ...BRADY, values: values(70, true) },
        ],
        supporting_cast: { value: 71 },
      },
    }));

    expect(screen.getByText(/round 2 of 6/i)).toBeInTheDocument();
    expect(screen.getByText("Denver Broncos")).toBeInTheDocument();
    expect(screen.getByText("2013")).toBeInTheDocument();
    expect(screen.getByRole("group", { name: "Peyton Manning" })).toBeInTheDocument();
    expect(screen.getByRole("group", { name: "Tom Brady" })).toBeInTheDocument();
    expect(screen.getAllByRole("radio", { name: /supporting cast/i })).toHaveLength(2);
  });

  it("shows Supporting Cast in every quarterback card and keeps those copies in sync", async () => {
    const user = userEvent.setup();
    renderScreen(boardOf({
      options: {
        quarterbacks: [
          { ...PEYTON, values: values(80, true) },
          { ...BRADY, values: values(70, true) },
        ],
        supporting_cast: { value: 71 },
      },
    }));

    const supportingCast = screen.getAllByRole("radio", { name: /supporting cast/i });
    expect(supportingCast).toHaveLength(2);
    await user.click(supportingCast[1]!);
    supportingCast.forEach((radio) => expect(radio).toBeChecked());
  });

  it("offers each of a quarterback's five qualities as its own option", () => {
    renderScreen(boardOf());

    const peyton = within(screen.getByRole("group", { name: "Peyton Manning" }));
    for (const quality of ["Accuracy", "Arm Talent", "Mobility", "IQ", "Build"]) {
      expect(peyton.getByRole("radio", { name: new RegExp(quality, "i") })).toBeEnabled();
    }
  });

  it("shows the six slots, filled and open", () => {
    renderScreen(boardOf({
      current_round: 3,
      picks: [
        { round: 1, slot: "accuracy", franchise_code: "kan", season: 2018, player_id: "00-0033873", display_name: "Patrick Mahomes", value: 90 },
        { round: 2, slot: "supporting_cast", franchise_code: "nwe", season: 2007, player_id: null, display_name: null, value: 88 },
      ],
    }));

    const slots = within(screen.getByRole("list", { name: "Your build" })).getAllByRole("listitem");
    expect(slots).toHaveLength(6);
    expect(slots.map((slot) => within(slot).queryByText("Open") !== null)).toEqual([false, true, true, true, true, false]);
    expect(within(slots[0]).getByText("Patrick Mahomes")).toBeInTheDocument();
    expect(within(slots[5]).getByText("New England Patriots")).toBeInTheDocument();
  });

  it("shows a picked quarterback's portrait beside their build source", () => {
    renderScreen(boardOf({
      current_round: 2,
      picks: [{ round: 1, slot: "accuracy", franchise_code: "den", season: 2013, ...PEYTON, value: 81 }],
    }));

    const accuracy = within(screen.getByRole("list", { name: "Your build" })).getAllByRole("listitem")[0];
    expect(accuracy?.querySelector("img")).toHaveAttribute("src", PEYTON.headshot_url);
  });
});

describe("QbSeasonBuilderMatch — modes", () => {
  it("shows 0-99 values beside the options in a visible run", () => {
    renderScreen(boardOf());

    expect(screen.getByRole("radio", { name: /accuracy/i }).closest("label")).toHaveTextContent("81");
    expect(screen.getByRole("radio", { name: /supporting cast/i }).closest("label")).toHaveTextContent("71");
    expect(screen.getByText(/ratings visible/i)).toBeInTheDocument();
  });

  it("shows no value anywhere on an option in a hidden run", () => {
    renderScreen(boardOf({ revealed: false }));

    for (const radio of screen.getAllByRole("radio")) {
      expect(radio.closest("label")).not.toHaveTextContent(/\d/);
    }
    expect(screen.getByText(/ratings hidden/i)).toBeInTheDocument();
  });

  it("gives a hidden run's picks no value either", () => {
    renderScreen(boardOf({
      revealed: false,
      current_round: 2,
      picks: [
        { round: 1, slot: "mobility", franchise_code: "bal", season: 2019, player_id: "00-0034796", display_name: "Lamar Jackson", value: null },
      ],
    }));

    const slots = within(screen.getByRole("list", { name: "Your build" })).getAllByRole("listitem");
    expect(within(slots[2]).getByText("Lamar Jackson")).toBeInTheDocument();
    // A season is four digits and may show; a rating is one or two and may not.
    expect(slots[2]).not.toHaveTextContent(/(?<!\d)\d{1,2}(?!\d)/);
  });

  it("has no control that changes the mode mid-run", () => {
    renderScreen(boardOf());

    expect(screen.queryByRole("switch")).not.toBeInTheDocument();
    expect(screen.queryByRole("radio", { name: /^(visible|hidden)/i })).not.toBeInTheDocument();
    expect(screen.queryByRole("button", { name: /visible|hidden|toggle/i })).not.toBeInTheDocument();
  });

  it("never says where the ratings came from", () => {
    const { container } = renderScreen(boardOf());

    expect(container).not.toHaveTextContent(/madden|ea sports/i);
  });
});
