import { act, fireEvent, render, screen, waitFor } from "@testing-library/react";
import userEvent from "@testing-library/user-event";
import { beforeEach, describe, expect, it, vi } from "vitest";

vi.mock("@/components/runtime/game-runtime/PostGameNavigation", () => ({
  PostGameNavigation: () => null,
}));
vi.mock("@/components/runtime/game-runtime/PostGameControls", () => ({
  PostGameControls: () => null,
}));

import { WavelengthMatch } from "./WavelengthMatch";
import type { Board, WavelengthResult, WavelengthRound } from "@/lib/games/wavelength/board";
import { dialPoint } from "@/lib/games/wavelength/board";
import { MATCH, supabaseMock } from "@/test/factories";

const board = { matchId: MATCH, mode: "coop" as const, preset: "short" as const, roundCount: 4, currentRound: 1, phase: "fill" as const, phaseDeadline: new Date(Date.now() + 30_000).toISOString(), serverNow: new Date().toISOString(), teamScores: [0] };
const players = [
  { match_id: MATCH, user_id: "u0", seat: 0, team: 0, absent: false, last_seen_at: "2026-01-01", display_name: "Ava", avatar_url: null },
  { match_id: MATCH, user_id: "u1", seat: 1, team: 0, absent: true, last_seen_at: "2026-01-01", display_name: "Ben", avatar_url: null },
];
const rounds = [{ match_id: MATCH, round: 1, psychic_id: "u0", guesser_id: "u1", status: "pending" as const, points: null, revealed_target: null, guess_position: null }];
const cards = [{ match_id: MATCH, round: 1, card_id: 1, left_label: "Overrated QB", right_label: "Underrated QB" }];

function match(phase: Board["phase"] = board.phase, viewerId = "u0", initialResult: WavelengthResult | null = null, initialRounds: WavelengthRound[] = rounds, initialBoard: Board = board, clueStatuses: { match_id: string; round: number }[] = [], initialCards = cards) {
  return render(<WavelengthMatch matchId={MATCH} viewerId={viewerId} roomCode="ABCD" isHost={false} initial={{ board: { ...initialBoard, phase }, players, rounds: initialRounds, cards: initialCards, clues: [], clueStatuses, result: initialResult }} />);
}

process.on("unhandledRejection", (reason) => { console.error("DEBUG unhandledRejection:", reason); });

describe("WavelengthMatch", () => {
  beforeEach(() => { globalThis.__supabaseMock = supabaseMock(); });

  it("blocks an invalid clue inline and marks absent players", async () => {
    const user = userEvent.setup();
    match();
    await user.type(screen.getByLabelText("Clue"), "Top 10");
    await user.click(screen.getByRole("button", { name: "Clue written" }));
    expect(screen.getByRole("alert")).toHaveTextContent("cannot contain digits");
    expect(screen.getByText("Ben").closest("p")).toHaveTextContent("Absent");
  });

  it("does not render scoring wedges during a guess", () => {
    match("guess");
    expect(screen.getByRole("slider", { name: "Guess needle" })).toBeInTheDocument();
    expect(screen.queryByText(/points/)).not.toBeInTheDocument();
  });

  it("renders a spectator's live needle Broadcast but ignores it for the guesser", async () => {
    const supabase = globalThis.__supabaseMock as ReturnType<typeof supabaseMock>;
    match("guess", "u0");
    await waitFor(() => expect(supabase.channel).toHaveBeenCalled());
    expect(supabase.channel).toHaveBeenCalledWith(`wavelength:${MATCH}`, { config: { private: true } });
    await act(async () => { supabase.emitBroadcast({ round: 1, position: 720 }); });
    expect(screen.getByRole("slider", { name: "Guess needle" })).toHaveAttribute("aria-valuenow", "720");

    // The guesser retains their immediate local position rather than taking a
    // delayed channel echo.
    match("guess", "u1");
    await waitFor(() => expect(supabase.channel).toHaveBeenCalledTimes(2));
    await act(async () => { supabase.emitBroadcast({ round: 1, position: 300 }); });
    expect(screen.getAllByRole("slider", { name: "Guess needle" })[1]).toHaveAttribute("aria-valuenow", "500");
  });

  it("throttles the active guesser's Broadcasts", async () => {
    const supabase = globalThis.__supabaseMock as ReturnType<typeof supabaseMock>;
    match("guess", "u1");
    await waitFor(() => expect(supabase.channel).toHaveBeenCalled());
    const dial = screen.getByRole("slider", { name: "Guess needle" });
    // A 1:1 box over the dial's viewBox (0 -270 1000 530).
    Object.defineProperty(dial, "getBoundingClientRect", { value: () => ({ left: 0, top: 0, width: 1000, height: 530 }) });
    const at = (position: number) => { const point = dialPoint(position); return { clientX: point.x, clientY: point.y + 270 }; };
    fireEvent.pointerDown(dial, at(250));
    fireEvent.pointerMove(dial, { buttons: 1, ...at(750) });
    expect(supabase.send).toHaveBeenCalledTimes(1);
    expect(supabase.send).toHaveBeenCalledWith({ type: "broadcast", event: "needle", payload: { round: 1, position: 250 } });
  });

  it("flashes a reveal banner for a round that just settled without hiding the next round's live board", async () => {
    // Heavier than its neighbors -- two sequential waitFors around a refetch
    // that Promise.all's eight mocked queries -- so give it more room than
    // the default 5s before a loaded CI runner calls it a hang.
    const supabase = globalThis.__supabaseMock as ReturnType<typeof supabaseMock>;
    const baseFrom = supabase.from.getMockImplementation()!;
    // Round 1 settles server-side -- the server itself jumps straight from
    // round 1's "guess" phase to round 2's, never pausing at "reveal" (see
    // wavelength_private.settle_guess), so this banner is the only reveal a
    // mid-match round ever gets.
    const settledRound1 = { ...rounds[0], status: "locked" as const, points: 3, revealed_target: 650, guess_position: 680 };
    const openRound2 = { ...rounds[0], round: 2, psychic_id: "u1", guesser_id: "u0", status: "open" as const };
    supabase.from.mockImplementation((table: string) => {
      const query = baseFrom(table) as { then: (resolve: (value: { data: unknown; error: null }) => unknown) => unknown };
      if (table === "wavelength_rounds") query.then = (resolve) => Promise.resolve({ data: [settledRound1, openRound2], error: null }).then(resolve);
      return query;
    });
    supabase.rpc.mockImplementation(async () => ({
      data: { match_id: MATCH, mode: "coop", preset: "short", round_count: 4, current_round: 2, phase: "guess", phase_deadline: new Date(Date.now() + 30_000).toISOString(), server_now: new Date().toISOString(), team_scores: [3] },
      error: null,
    }));
    const round2Card = { ...cards[0], round: 2, card_id: 2, left_label: "Left 2", right_label: "Right 2" };
    console.error("DEBUG checkpoint A: rendering");
    match("guess", "u0", null, [{ ...rounds[0], status: "open" }], board, [], [cards[0], round2Card]);
    console.error("DEBUG checkpoint B: waiting for channel");
    await waitFor(() => expect(supabase.channel).toHaveBeenCalled());
    console.error("DEBUG checkpoint C: channel seen, emitting");
    // Any change to the match row is enough to make the client reconcile --
    // this is how a settle another player triggered reaches this screen too.
    await act(async () => { supabase.emit("wavelength_matches", {}); });
    console.error("DEBUG checkpoint D: emitted, waiting for status");
    await waitFor(() => expect(screen.getByRole("status")).toHaveTextContent("So close!"));
    console.error("DEBUG checkpoint E: status seen");
    expect(screen.getByRole("status")).toHaveTextContent("3 points");
    // Round 2's own board, underneath the banner, is still fully live.
    expect(screen.getByRole("slider", { name: "Guess needle" })).toBeInTheDocument();
    expect(screen.getByText("Left 2")).toBeInTheDocument();
    console.error("DEBUG checkpoint F: done");
  }, 15000);

  it("lets a psychic who owns several rounds write each clue in turn", async () => {
    const user = userEvent.setup();
    const supabase = globalThis.__supabaseMock as ReturnType<typeof supabaseMock>;
    const mine = [
      { ...rounds[0], round: 1, psychic_id: "u1", guesser_id: "u0" },
      { ...rounds[0], round: 2, psychic_id: "u0", guesser_id: "u1" },
      { ...rounds[0], round: 3, psychic_id: "u0", guesser_id: "u1" },
    ];
    const deck = [1, 2, 3].map((round) => ({ ...cards[0], round, card_id: round, left_label: `Left ${round}`, right_label: `Right ${round}` }));
    // Round 2 is already written, so the form must move on to round 3 -- not
    // stay on the board's current round (1), which belongs to a teammate.
    match("fill", "u0", null, mine, board, [{ match_id: MATCH, round: 2 }], deck);
    expect(screen.getByText("Left 3")).toBeInTheDocument();
    await user.type(screen.getByLabelText("Clue"), "Comeback kings");
    await user.click(screen.getByRole("button", { name: "Clue written" }));
    expect(supabase.rpc).toHaveBeenCalledWith("submit_clue", { p_match_id: MATCH, p_round: 3, p_clue: "Comeback kings" });
  });

  it("shows the psychic their target on the dial while they write the clue", async () => {
    const supabase = globalThis.__supabaseMock as ReturnType<typeof supabaseMock>;
    const baseFrom = supabase.from.getMockImplementation()!;
    supabase.from.mockImplementation((table: string) => {
      // Mutate (not replace) the chainable query object: `.select()`/`.eq()`
      // close over this same object, so a replacement would be discarded the
      // moment the component chains another call onto it.
      const query = baseFrom(table) as { then: (resolve: (value: { data: unknown; error: null }) => unknown) => unknown };
      if (table === "wavelength_targets") {
        query.then = (resolve) => Promise.resolve({ data: [{ match_id: MATCH, round: 1, target: 650 }], error: null }).then(resolve);
      }
      return query;
    });
    match("fill", "u0");
    // The dial renders once the psychic's own target has loaded, before any
    // guess has happened -- this is the whole point of Wavelength: you aim
    // the clue at a target you can see, not a blank spectrum.
    await waitFor(() => expect(screen.getByRole("slider", { name: "Guess needle" })).toBeInTheDocument());
    expect(document.querySelectorAll("svg[role=slider] path")).toHaveLength(6);
  });

  it("tells a psychic with every clue written to wait", () => {
    match("fill", "u0", null, rounds, board, [{ match_id: MATCH, round: 1 }]);
    expect(screen.queryByLabelText("Clue")).not.toBeInTheDocument();
    expect(screen.getByText(/Your clues are written/)).toBeInTheDocument();
  });

  it("shows the psychic the wedges for their own round only", () => {
    match("guess", "u0");
    expect(document.querySelectorAll("svg[role=slider] path")).toHaveLength(1);
  });

  it("shows the stored co-op result including score, bullseyes, outcome, and stars", () => {
    match("complete", "u0", { match_id: MATCH, mode: "coop", preset: "short", outcome: "win", score: 12, bullseyes: 2, stars: 2 });
    expect(screen.getByText("You won!")).toBeInTheDocument();
    expect(screen.getByText("12 / 16 points")).toBeInTheDocument();
    expect(screen.getByText("2 bullseyes")).toBeInTheDocument();
    expect(screen.getByLabelText("2 star tier")).toHaveTextContent("★★☆");
  });

  it("shows versus totals, winner, and a sudden-death finish", () => {
    const suddenDeathRounds = [...rounds, { ...rounds[0], round: 2 }];
    match("complete", "u0", { match_id: MATCH, mode: "versus", preset: null, outcome: "team_1_win", score: 10, bullseyes: 2, stars: null }, suddenDeathRounds, { ...board, mode: "versus", roundCount: 1, teamScores: [8, 10] });
    expect(screen.getByText("Team 2 wins!")).toBeInTheDocument();
    expect(screen.getByText("Team 1: 8")).toBeInTheDocument();
    expect(screen.getByText("Team 2: 10")).toBeInTheDocument();
    expect(screen.getByText("Sudden death")).toBeInTheDocument();
  });

  it("identifies a tied versus total settled by bullseyes", () => {
    match("complete", "u0", { match_id: MATCH, mode: "versus", preset: null, outcome: "team_0_win", score: 8, bullseyes: 2, stars: null }, rounds, { ...board, mode: "versus", teamScores: [8, 8] });
    expect(screen.getByText("Team 1 wins!")).toBeInTheDocument();
    expect(screen.getByText("Bullseye tiebreak")).toBeInTheDocument();
  });
});
