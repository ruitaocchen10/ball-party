import { act, render, screen, within } from "@testing-library/react";
import userEvent from "@testing-library/user-event";
import { beforeEach, describe, expect, it, vi } from "vitest";

vi.mock("@/components/runtime/game-runtime/PostGameNavigation", () => ({
  PostGameNavigation: () => null,
}));

import { HigherOrLowerMatch } from "@/components/games/higher-or-lower/HigherOrLowerMatch";
import type { Board, Call, CallStatus, Card, Player, Standing } from "@/lib/games/higher-or-lower/board";
import { supabaseMock } from "@/test/factories";

/**
 * The match screen, at the slice where a ladder exists and nothing can be
 * called yet.
 *
 * jsdom on purpose: everything asserted here is behaviour the component
 * decides — which two cards the table is looking at, which number is on screen
 * and which is withheld. Whether the concealed weave is actually red, and
 * whether the two cards sit side by side at this width, are questions only a
 * CSS engine can answer and are out of reach here rather than faked with a
 * class assertion.
 *
 * The withholding is asserted twice over, because a screen is the weakest half
 * of it: the number is absent from the DOM, not merely styled out of the way.
 * The server-side half — that the row never carried the number at all — is
 * supabase/tests/0032_higher_or_lower_board.test.sql.
 */

const MATCH = "11111111-1111-1111-1111-111111111111";

function card(over: Partial<Card> = {}): Card {
  return {
    match_id: MATCH,
    ordinal: 0,
    player_id: "00-0000001",
    display_name: "Saquon Barkley",
    position: "RB",
    season: 2018,
    team: "NYG",
    week: null,
    opponent: null,
    headshot_url: "https://static.www.nfl.com/image/private/f_auto,q_auto/league/abc",
    points: null,
    revealed_at: null,
    ...over,
  };
}

/** The anchor face up, then three challengers with their points withheld. */
function ladder(): Card[] {
  return [
    card({ ordinal: 0, display_name: "Saquon Barkley", points: 289.4, revealed_at: "2026-08-15T12:00:00Z" }),
    card({ ordinal: 1, display_name: "Patrick Mahomes", position: "QB", season: 2019, team: "KC" }),
    card({ ordinal: 2, display_name: "Justin Jefferson", position: "WR", season: 2022, team: "MIN" }),
    card({ ordinal: 3, display_name: "Travis Kelce", position: "TE", season: 2020, team: "KC" }),
  ];
}

/**
 * A call, or the absence of one. A timeout is a row like any other with no
 * direction on it and the flag set — the server writes it at the reveal, and
 * the screen's job is to say "timed out" where it would otherwise say "wrong".
 */
function call(over: Partial<Call> = {}): Call {
  return {
    match_id: MATCH,
    question: 1,
    user_id: "u0",
    direction: "higher",
    timed_out: false,
    created_at: "2026-08-15T12:00:00Z",
    ...over,
  };
}

function miss(over: Partial<Call> = {}): Call {
  return call({ direction: null, timed_out: true, ...over });
}

const BOARD: Board = {
  questionCount: 12,
  currentQuestion: 1,
  scoringMode: "season_total",
  seasonFrom: 2010,
  seasonTo: 2025,
  phase: "call",
  phaseDeadline: new Date(Date.now() + 12_000).toISOString(),
  serverNow: new Date().toISOString(),
};

const SEEN = "2026-08-15T12:00:00Z";

const PLAYERS: Player[] = [
  { match_id: MATCH, user_id: "u0", seat: 0, current_streak: 2, best_streak: 3, correct_count: 5, absent: false, last_seen_at: SEEN, sudden_death: false, eliminated_at: null, display_name: "Ava", avatar_url: null },
  { match_id: MATCH, user_id: "u1", seat: 1, current_streak: 0, best_streak: 1, correct_count: 1, absent: false, last_seen_at: SEEN, sudden_death: false, eliminated_at: null, display_name: "Ben", avatar_url: null },
];

function standing(over: Partial<Standing> = {}): Standing {
  return {
    match_id: MATCH,
    run_id: "run-1",
    user_id: "u0",
    team: null,
    raw_score: 3,
    placement: 1,
    points_awarded: null,
    ...over,
  };
}

function renderMatch(over: {
  board?: Partial<Board>;
  cards?: Card[];
  players?: Player[];
  calls?: Call[];
  statuses?: CallStatus[];
  standings?: Standing[];
  roomCode?: string | null;
  isHost?: boolean;
  paused?: boolean;
  viewerId?: string;
  allTimeHigh?: number;
} = {}) {
  return render(
    <HigherOrLowerMatch
      matchId={MATCH}
      viewerId={over.viewerId ?? "u0"}
      roomCode={over.roomCode === undefined ? "ABCD" : over.roomCode}
      isHost={over.isHost ?? true}
      paused={over.paused ?? false}
      initial={{
        board: { ...BOARD, ...over.board },
        cards: over.cards ?? ladder(),
        players: over.players ?? PLAYERS,
        calls: over.calls ?? [],
      statuses: over.statuses ?? [],
      standings: over.standings ?? [],
      allTimeHigh: over.allTimeHigh ?? 0,
      }}
    />,
  );
}

describe("HigherOrLowerMatch", () => {
  beforeEach(() => {
    globalThis.__supabaseMock = supabaseMock();
  });

  it("shows the shared phase and its server-timed countdown", () => {
    renderMatch({ board: { phase: "call", phaseDeadline: new Date(Date.now() + 9_000).toISOString() } });

    expect(screen.getByRole("region", { name: /clock/i })).toHaveTextContent("Make your call");
    expect(screen.getByRole("timer", { name: /seconds left/i })).toBeInTheDocument();
  });

  it("puts the higher-or-lower decision on the challenger card", () => {
    renderMatch();

    const challenger = screen.getByRole("group", { name: "Challenger" });
    expect(within(challenger).getByRole("button", { name: "Higher" })).toBeInTheDocument();
    expect(within(challenger).getByRole("button", { name: "Lower" })).toBeInTheDocument();
    expect(screen.getByRole("group", { name: "Anchor" })).not.toContainElement(screen.getByRole("button", { name: "Higher" }));
  });

  it("keeps the card roles semantic without showing anchor and challenger headers", () => {
    renderMatch();

    expect(screen.getByRole("group", { name: "Anchor" })).toBeInTheDocument();
    expect(screen.getByRole("group", { name: "Challenger" })).toBeInTheDocument();
    expect(screen.queryByText("Anchor", { exact: true })).not.toBeInTheDocument();
    expect(screen.queryByText("Challenger", { exact: true })).not.toBeInTheDocument();
  });

  it("accepts one higher-or-lower call and disables both controls", async () => {
    const user = userEvent.setup();
    globalThis.__supabaseMock.rpc.mockImplementation(async (name: unknown) => name === "call"
      ? { data: { match_id: MATCH, question: 1, user_id: "u0", direction: "higher", created_at: new Date().toISOString() }, error: null }
      : { data: null, error: null });
    renderMatch();

    await user.click(screen.getByRole("button", { name: "Higher" }));

    expect(globalThis.__supabaseMock.schema).toHaveBeenCalledWith("higher_or_lower");
    expect(globalThis.__supabaseMock.rpc).toHaveBeenCalledWith("call", {
      p_match_id: MATCH,
      p_direction: "higher",
    });
    expect(screen.getByRole("button", { name: "Higher" })).toBeDisabled();
    expect(screen.getByRole("button", { name: "Lower" })).toBeDisabled();
    expect(screen.getByText("You called higher.")).toBeInTheDocument();
  });

  it("shows every lock-in but only directions supplied by the policy", () => {
    renderMatch({
      calls: [call({ user_id: "u0", direction: "lower" })],
      statuses: [
        { match_id: MATCH, question: 1, user_id: "u0" },
        { match_id: MATCH, question: 1, user_id: "u1" },
      ],
    });

    expect(screen.getAllByText("LOCKED")).toHaveLength(1);
    expect(screen.getByText("You called lower.")).toBeInTheDocument();
    expect(screen.queryByText(/Ben called/i)).not.toBeInTheDocument();
  });

  it("orders the live standings by total correct answers, then best streak", () => {
    renderMatch({
      players: [
        { ...PLAYERS[0], best_streak: 6, correct_count: 6 },
        { ...PLAYERS[1], best_streak: 4, correct_count: 7 },
        { ...PLAYERS[1], user_id: "u2", seat: 2, display_name: "Cam", best_streak: 3, correct_count: 5 },
      ],
    });

    const rows = within(screen.getByRole("complementary", { name: /the table/i })).getAllByRole("listitem");
    expect(rows.map((row) => row.textContent)).toEqual([
      expect.stringMatching(/#1.*Ben/),
      expect.stringMatching(/#2.*Ava/),
      expect.stringMatching(/#3.*Cam/),
    ]);
  });

  // The server scores a timeout exactly as it scores a wrong call, on purpose.
  // The screen is the one place the two are meant to look different, which is
  // the entire reason the row carries a flag rather than just a null direction.
  it("tells a player who ran out of time apart from one who called wrong", () => {
    renderMatch({
      board: { phase: "reveal" },
      calls: [call({ user_id: "u0", direction: "lower" }), miss({ user_id: "u1" })],
      statuses: [{ match_id: MATCH, question: 1, user_id: "u0" }],
    });

    const table = screen.getByRole("complementary", { name: /the table/i });
    expect(table).toHaveTextContent("lower");
    expect(table).toHaveTextContent("TIMED OUT");
    expect(screen.queryByText("LOCKED")).not.toBeInTheDocument();
  });

  it("says plainly when the clock ran out on you rather than reporting a call", () => {
    renderMatch({ board: { phase: "reveal" }, calls: [miss({ user_id: "u0" })] });

    expect(screen.getByText("You ran out of time.")).toBeInTheDocument();
    expect(screen.queryByText(/You called/)).not.toBeInTheDocument();
  });

  // Absence is the server's judgement, latched over a whole question. The
  // screen only reports it, so that the table can see why it stopped waiting.
  it("marks a player the server has stopped waiting for", () => {
    renderMatch({
      players: [PLAYERS[0], { ...PLAYERS[1], absent: true }],
    });

    const table = screen.getByRole("complementary", { name: /the table/i });
    expect(table).toHaveTextContent("AWAY");
  });

  it("shows a challenger's points once the server says its reveal is live", () => {
    renderMatch({
      board: { phase: "reveal" },
      cards: [
        card({ ordinal: 0, points: 289.4, revealed_at: "2026-08-15T12:00:00Z" }),
        card({ ordinal: 1, display_name: "Patrick Mahomes", points: 417.1, revealed_at: "2026-08-15T12:01:00Z" }),
      ],
    });

    expect(screen.getByRole("group", { name: /challenger/i })).toHaveTextContent("417.1");
    expect(screen.queryByText("? ? ?")).not.toBeInTheDocument();
  });

  it("keeps a reordered card update concealed until its reveal phase arrives", () => {
    renderMatch({
      board: { phase: "call" },
      cards: [
        card({ ordinal: 0, points: 289.4, revealed_at: "2026-08-15T12:00:00Z" }),
        card({ ordinal: 1, display_name: "Patrick Mahomes", points: 417.1, revealed_at: "2026-08-15T12:01:00Z" }),
      ],
    });

    expect(screen.getByRole("group", { name: /challenger/i })).toHaveTextContent("? ? ?");
    expect(screen.getByRole("group", { name: /challenger/i })).not.toHaveTextContent("417.1");
  });

  it("shows the anchor with its points and the challenger with them withheld", () => {
    renderMatch();

    const anchor = screen.getByRole("group", { name: /anchor/i });
    expect(anchor).toHaveTextContent("Saquon Barkley");
    expect(anchor).toHaveTextContent("289.4");

    const challenger = screen.getByRole("group", { name: /challenger/i });
    expect(challenger).toHaveTextContent("Patrick Mahomes");
    expect(challenger).toHaveTextContent("? ? ?");
    expect(challenger).not.toHaveTextContent("289.4");
  });

  // The concealed panel's face is out of the accessibility tree, the way the
  // auction's is, so the status region is the whole announcement rather than
  // one of two competing ones.
  it("announces the pair, including which number is being withheld", () => {
    renderMatch();

    expect(screen.getByRole("status")).toHaveTextContent(
      "Question 1 of 12. Saquon Barkley scored 289.4 fantasy points. Patrick Mahomes is hidden.",
    );
  });

  it("names the question and how many there are", () => {
    renderMatch();

    expect(screen.getByText("Question 1 of 12")).toBeInTheDocument();
  });

  it("uses an open-ended question count after the solo ladder's fixed opening", () => {
    renderMatch({
      board: { currentQuestion: 13 },
      cards: [
        card({ ordinal: 12, points: 289.4, revealed_at: "2026-08-15T12:00:00Z" }),
        card({ ordinal: 13, display_name: "Patrick Mahomes" }),
      ],
    });

    expect(screen.getByText("Question 13")).toBeInTheDocument();
    expect(screen.queryByText(/Question 13 of/)).not.toBeInTheDocument();
    expect(screen.getByRole("status")).toHaveTextContent("Question 13.");
  });

  it("gives each card the cues a call is made from", () => {
    renderMatch();

    expect(screen.getByRole("group", { name: /anchor/i })).toHaveTextContent("2018 seasonNYG");
    expect(screen.getByRole("group", { name: /challenger/i })).toHaveTextContent("2019 seasonKC");
  });

  // The row's week and opponent are nullable — null for a whole season, set for
  // one game — so both shapes are rendered here. Only season mode deals today;
  // weekly boards are #29.
  it("names the week and the opponent on a card that has them", () => {
    renderMatch({
      cards: [
        card({ ordinal: 0, points: 24.6, revealed_at: "2026-08-15T12:00:00Z", week: 12, opponent: "CHI" }),
        card({ ordinal: 1, display_name: "Patrick Mahomes", position: "QB", season: 2019, team: "KC", week: 4, opponent: "DET" }),
      ],
      board: { scoringMode: "weekly" },
    });

    expect(screen.getByLabelText("2018, week 12, NYG versus CHI")).toBeInTheDocument();
    expect(screen.getByLabelText("2019, week 4, KC versus DET")).toBeInTheDocument();
  });

  // The ladder climbs: every card is a challenger once and the anchor after
  // that, so the pair the table is looking at is the current question and the
  // card before it rather than two fixed rows.
  it("moves both cards along as the question advances", () => {
    renderMatch({
      board: { currentQuestion: 3 },
      cards: [
        card({ ordinal: 0, display_name: "Saquon Barkley", points: 289.4, revealed_at: "2026-08-15T12:00:00Z" }),
        card({ ordinal: 1, display_name: "Patrick Mahomes", points: 417.1, revealed_at: "2026-08-15T12:01:00Z" }),
        card({ ordinal: 2, display_name: "Justin Jefferson", points: 368.2, revealed_at: "2026-08-15T12:02:00Z" }),
        card({ ordinal: 3, display_name: "Travis Kelce" }),
      ],
    });

    expect(screen.getByRole("group", { name: /anchor/i })).toHaveTextContent("Justin Jefferson");
    expect(screen.getByRole("group", { name: /anchor/i })).toHaveTextContent("368.2");
    expect(screen.getByRole("group", { name: /challenger/i })).toHaveTextContent("Travis Kelce");
    expect(screen.queryByText("417.1")).not.toBeInTheDocument();
    expect(screen.getByText("Question 3 of 12")).toBeInTheDocument();
  });

  it("says who is at the table and what the board was dealt from", () => {
    renderMatch();

    expect(screen.getByText("Ava")).toBeInTheDocument();
    expect(screen.getByText("Ben")).toBeInTheDocument();
    expect(screen.getByText("2 now · 3 best · 5 correct")).toBeInTheDocument();
    expect(screen.getByRole("note", { name: /format/i })).toHaveTextContent("season total · 2010-2025");
  });

  // A card the server has not sent yet is a normal state, not a crash: the
  // screen renders through it rather than blanking.
  it("waits rather than breaking when the next card has not arrived", () => {
    renderMatch({ board: { currentQuestion: 9 } });

    expect(screen.getByText(/waiting for the next card/i)).toBeInTheDocument();
  });

  // Endless solo (0046) appends a brand-new ordinal past the pre-dealt
  // twelve, which arrives over Realtime as an INSERT — not an update to a
  // card already on screen. The bug this guards: the card handler used to
  // `.map()` looking for a matching ordinal, found none, and silently
  // dropped the row, so the ladder looked stuck at question twelve forever.
  it("picks up a card the ladder extends past its pre-dealt ordinal", async () => {
    renderMatch({
      board: { currentQuestion: 12 },
      cards: [
        ...ladder(),
        card({ ordinal: 4, revealed_at: "2026-08-15T12:04:00Z" }),
        card({ ordinal: 5, revealed_at: "2026-08-15T12:05:00Z" }),
        card({ ordinal: 6, revealed_at: "2026-08-15T12:06:00Z" }),
        card({ ordinal: 7, revealed_at: "2026-08-15T12:07:00Z" }),
        card({ ordinal: 8, revealed_at: "2026-08-15T12:08:00Z" }),
        card({ ordinal: 9, revealed_at: "2026-08-15T12:09:00Z" }),
        card({ ordinal: 10, revealed_at: "2026-08-15T12:10:00Z" }),
        card({ ordinal: 11, points: 289.4, revealed_at: "2026-08-15T12:11:00Z" }),
        card({ ordinal: 12, display_name: "Ja'Marr Chase" }),
      ],
    });

    // The channel subscribes inside an async effect (it awaits
    // createRealtimeClient()), so a tick has to pass before `.on()` has run
    // and `emit` has a handler to reach.
    await act(async () => {});

    act(() => {
      globalThis.__supabaseMock.emit(
        "higher_or_lower_cards",
        card({ ordinal: 13, display_name: "CeeDee Lamb" }),
      );
      globalThis.__supabaseMock.emit("higher_or_lower_matches", {
        match_id: MATCH,
        question_count: 12,
        current_question: 13,
        scoring_mode: "season_total",
        season_from: 2010,
        season_to: 2025,
        phase: "call",
        phase_deadline: null,
      });
    });

    expect(screen.getByRole("group", { name: /challenger/i })).toHaveTextContent("CeeDee Lamb");
  });
});

/**
 * A tied top best streak (#28) puts the same screen through two more phases,
 * a strict subset of players, and a shorter clock. The card panels, the
 * lock-in indicators and the reveal split are the same mechanism reused —
 * only the header, the clock and who may call are new — so those are what
 * this block asserts.
 */
describe("sudden death", () => {
  const TIED: Player[] = [
    { ...PLAYERS[0], sudden_death: true, eliminated_at: null },
    { ...PLAYERS[1], sudden_death: true, eliminated_at: null },
  ];

  it("names the round instead of the question", () => {
    renderMatch({
      board: { phase: "sudden_death_call", currentQuestion: 13 },
      players: TIED,
      cards: [
        card({ ordinal: 12, points: 368.2, revealed_at: "2026-08-15T12:12:00Z" }),
        card({ ordinal: 13, display_name: "Travis Kelce" }),
      ],
    });

    expect(screen.getByText("Sudden death · Round 1")).toBeInTheDocument();
    expect(screen.queryByText(/^Question/)).not.toBeInTheDocument();
  });

  it("gives sudden death an eight-second clock, not the main round's twelve", () => {
    renderMatch({
      board: {
        phase: "sudden_death_call",
        currentQuestion: 13,
        phaseDeadline: new Date(Date.now() + 8_000).toISOString(),
      },
      players: TIED,
    });

    expect(screen.getByRole("region", { name: /clock/i })).toHaveTextContent("Make your call");
  });

  it("reveals the challenger after a sudden-death round", () => {
    renderMatch({
      board: { phase: "sudden_death_reveal", currentQuestion: 13 },
      players: TIED,
      cards: [
        card({ ordinal: 12, display_name: "Justin Jefferson", points: 368.2, revealed_at: "2026-08-15T12:12:00Z" }),
        card({ ordinal: 13, display_name: "Travis Kelce", points: 417.1, revealed_at: "2026-08-15T12:13:00Z" }),
      ],
    });

    expect(screen.getByRole("group", { name: /challenger/i })).toHaveTextContent("417.1");
  });

  it("lets an admitted, still-alive player call", async () => {
    const user = userEvent.setup();
    globalThis.__supabaseMock.rpc.mockImplementation(async (name: unknown) => name === "call"
      ? { data: { match_id: MATCH, question: 13, user_id: "u0", direction: "higher", timed_out: false, created_at: new Date().toISOString() }, error: null }
      : { data: null, error: null });
    renderMatch({
      board: { phase: "sudden_death_call", currentQuestion: 13 },
      players: TIED,
      cards: [
        card({ ordinal: 12, points: 368.2, revealed_at: "2026-08-15T12:12:00Z" }),
        card({ ordinal: 13, display_name: "Travis Kelce" }),
      ],
    });

    await user.click(screen.getByRole("button", { name: "Higher" }));

    expect(screen.getByText("You called higher.")).toBeInTheDocument();
  });

  // Sudden death admits a strict subset; everyone else's placement is already
  // settled, and the server refuses their call outright — the screen only
  // has to not offer a control the RPC would reject anyway.
  it("does not let a player who was never tied call", () => {
    renderMatch({
      board: { phase: "sudden_death_call", currentQuestion: 13 },
      players: [TIED[0], { ...PLAYERS[1], sudden_death: false, eliminated_at: null }],
      viewerId: "u1",
      cards: [
        card({ ordinal: 12, points: 368.2, revealed_at: "2026-08-15T12:12:00Z" }),
        card({ ordinal: 13, display_name: "Travis Kelce" }),
      ],
    });

    expect(screen.getByRole("button", { name: "Higher" })).toBeDisabled();
    expect(screen.getByRole("button", { name: "Lower" })).toBeDisabled();
  });

  it("does not let an eliminated player call again", () => {
    renderMatch({
      board: { phase: "sudden_death_call", currentQuestion: 14 },
      players: [TIED[0], { ...PLAYERS[1], sudden_death: true, eliminated_at: 13 }],
      viewerId: "u1",
      cards: [
        card({ ordinal: 13, points: 417.1, revealed_at: "2026-08-15T12:13:00Z" }),
        card({ ordinal: 14, display_name: "CeeDee Lamb" }),
      ],
    });

    expect(screen.getByRole("button", { name: "Higher" })).toBeDisabled();
  });

  it("marks an eliminated player apart from one still watching", () => {
    renderMatch({
      board: { phase: "sudden_death_call", currentQuestion: 14 },
      players: [
        { ...TIED[0], eliminated_at: 13 },
        { ...PLAYERS[1], sudden_death: false, eliminated_at: null },
      ],
    });

    const table = screen.getByRole("complementary", { name: /the table/i });
    expect(table).toHaveTextContent("ELIMINATED");
    expect(table).toHaveTextContent("WATCHING");
  });

  it("keeps surviving sudden-death contenders above eliminated and watching players", () => {
    renderMatch({
      board: { phase: "sudden_death_call", currentQuestion: 14 },
      players: [
        { ...TIED[0], eliminated_at: 13 },
        TIED[1],
        { ...PLAYERS[1], user_id: "u2", seat: 2, display_name: "Cam", sudden_death: false },
      ],
    });

    const rows = within(screen.getByRole("complementary", { name: /the table/i })).getAllByRole("listitem");
    expect(rows.map((row) => row.textContent)).toEqual([
      expect.stringMatching(/#1.*Ben/),
      expect.stringMatching(/#2.*Ava/),
      expect.stringMatching(/#3.*Cam/),
    ]);
  });
});

/**
 * The ending (#28): a final scoreboard read from the platform's standings,
 * and the same play-again-or-back-to-the-room the auction's final screen
 * offers, reused rather than reinvented (components/game-runtime).
 */
describe("the final screen", () => {
  it("names the sole winner and ranks the table under them", () => {
    renderMatch({
      board: { phase: "complete" },
      players: PLAYERS,
      standings: [
        standing({ user_id: "u0", placement: 1, raw_score: 3 }),
        standing({ user_id: "u1", placement: 2, raw_score: 1 }),
      ],
    });

    expect(screen.getByRole("heading", { name: "Ava wins" })).toBeInTheDocument();
    const rows = screen.getAllByRole("listitem");
    expect(rows[0]).toHaveTextContent("Ava");
    expect(rows[1]).toHaveTextContent("Ben");
  });

  // Co-winners are the accepted last resort (#28's exhausted-spares fallback),
  // not a bug this screen should hide by picking one name.
  it("names every co-winner when the standings share first place", () => {
    renderMatch({
      board: { phase: "complete" },
      players: PLAYERS,
      standings: [
        standing({ user_id: "u0", placement: 1, raw_score: 3 }),
        standing({ user_id: "u1", placement: 1, raw_score: 3 }),
      ],
    });

    expect(screen.getByRole("heading", { name: "Ava & Ben tie" })).toBeInTheDocument();
  });

  it("offers to play again or go back to the room", () => {
    renderMatch({
      board: { phase: "complete" },
      players: PLAYERS,
      standings: [standing({ user_id: "u0", placement: 1 })],
      isHost: true,
    });

    expect(screen.getByRole("button", { name: /replay/i })).toBeInTheDocument();
    expect(screen.getByRole("button", { name: /back to lobby/i })).toBeInTheDocument();
  });

  it("offers a solo player another match alongside the home link", () => {
    const revealed = [
      card({ ordinal: 0, display_name: "Saquon Barkley", points: 289.4, revealed_at: SEEN }),
      card({ ordinal: 1, display_name: "Patrick Mahomes", points: 417.1, revealed_at: SEEN }),
    ];
    renderMatch({
      board: { phase: "complete" },
      players: [PLAYERS[0]],
      standings: [standing({ user_id: "u0", placement: 1 })],
      roomCode: null,
      cards: revealed,
      calls: [call({ question: 1, direction: "higher" })],
      allTimeHigh: 8,
    });

    const result = screen.getByRole("region", { name: "Your final result" });
    expect(result).toBeInTheDocument();
    expect(screen.getByRole("heading", { name: "Run summary" })).toBeInTheDocument();
    expect(within(result).getByText("All time high")).toBeInTheDocument();
    expect(within(result).getByText("All time high").parentElement).toHaveTextContent("8");
    const recap = screen.getByRole("region", { name: "Your ladder" });
    expect(within(recap).getByText("Saquon Barkley")).toBeInTheDocument();
    expect(within(recap).getByText("Patrick Mahomes")).toBeInTheDocument();
    expect(within(recap).getByText("Called higher · correct")).toBeInTheDocument();
    expect(screen.getByRole("button", { name: /play again/i })).toBeInTheDocument();
    expect(screen.getByRole("link", { name: /back home/i })).toBeInTheDocument();
  });
});

// A solo run has no lobby, so roomCode is null the way FinalScreen's own
// branch above already reads it. Solo has no other player to keep pace with,
// so it drops the clock this suite's default group board keeps: see
// migration 0084.
describe("solo pacing", () => {
  beforeEach(() => {
    globalThis.__supabaseMock = supabaseMock();
  });

  it("names the question without a fixed count and shows no clock", () => {
    renderMatch({ roomCode: null, board: { phaseDeadline: null } });

    expect(screen.getByText("Question 1")).toBeInTheDocument();
    expect(screen.queryByText("Question 1 of 12")).not.toBeInTheDocument();
    expect(screen.queryByRole("region", { name: /clock/i })).not.toBeInTheDocument();
  });

  it("offers a continue button on a reveal instead of an auto-advancing clock", async () => {
    const user = userEvent.setup();
    globalThis.__supabaseMock.rpc.mockImplementation(async (name: unknown) => name === "advance"
      ? { data: { ...BOARD, phase: "call", current_question: 2 }, error: null }
      : { data: null, error: null });
    renderMatch({
      roomCode: null,
      board: { phase: "reveal", phaseDeadline: null },
      cards: [
        card({ ordinal: 0, points: 289.4, revealed_at: SEEN }),
        card({ ordinal: 1, display_name: "Patrick Mahomes", points: 417.1, revealed_at: SEEN }),
      ],
    });

    expect(screen.queryByRole("region", { name: /clock/i })).not.toBeInTheDocument();
    const run = screen.getByRole("complementary", { name: "Higher or lower" });
    expect(within(run).getByText("Current")).toBeInTheDocument();
    expect(within(run).getByText("All time high")).toBeInTheDocument();
    expect(within(run).queryByText("Correct")).not.toBeInTheDocument();
    expect(within(run).getByRole("button", { name: "Continue" })).toBeInTheDocument();
    await user.click(screen.getByRole("button", { name: "Continue" }));

    expect(globalThis.__supabaseMock.schema).toHaveBeenCalledWith("higher_or_lower");
    expect(globalThis.__supabaseMock.rpc).toHaveBeenCalledWith("advance", { p_match_id: MATCH });
  });

  it("keeps the group board's clock and offers no continue button", () => {
    renderMatch({ board: { phase: "reveal", phaseDeadline: new Date(Date.now() + 4_000).toISOString() } });

    expect(screen.getByRole("region", { name: /clock/i })).toBeInTheDocument();
    expect(screen.queryByRole("button", { name: "Continue" })).not.toBeInTheDocument();
  });
});

describe("pausing", () => {
  beforeEach(() => {
    globalThis.__supabaseMock = supabaseMock();
  });

  it("gives only the host a pause control", () => {
    renderMatch({ isHost: false });
    expect(screen.queryByRole("button", { name: "Pause" })).not.toBeInTheDocument();

    renderMatch({ isHost: true });
    expect(screen.getByRole("button", { name: "Pause" })).toBeInTheDocument();
  });

  it("asks the server to pause the match", async () => {
    const user = userEvent.setup();
    renderMatch({ isHost: true });

    await user.click(screen.getByRole("button", { name: "Pause" }));
    expect(globalThis.__supabaseMock.rpc).toHaveBeenCalledWith("pause_match", { p_match_id: MATCH });
  });

  it("shows everybody the paused banner and disables the call buttons", () => {
    renderMatch({ paused: true });

    expect(screen.getByText("Paused")).toBeInTheDocument();
    expect(screen.getByRole("button", { name: "Higher" })).toBeDisabled();
    expect(screen.getByRole("button", { name: "Lower" })).toBeDisabled();
  });
});

/**
 * Presence rides on the tick RPC this screen already calls. A screen that only
 * asked when a deadline had passed would put nobody on the record during a
 * question, and the server would latch the whole table absent at its reveal —
 * so the wiring that makes this screen keep asking is behaviour, not detail.
 */
describe("staying at the table", () => {
  // Date faked alongside the interval, for the reason the clock module's own
  // suite gives: the countdown reads Date.now() plus a measured offset, so a
  // fake interval driving a real clock advances ticks without advancing time.
  const withFakeTimers = async (body: () => Promise<void>) => {
    vi.useFakeTimers({
      toFake: ["setInterval", "clearInterval", "setTimeout", "clearTimeout", "Date"],
    });
    try {
      await body();
    } finally {
      vi.useRealTimers();
    }
  };

  const advance = async (ms: number, step = 500) => {
    for (let elapsed = 0; elapsed < ms; elapsed += step) {
      await act(async () => {
        await vi.advanceTimersByTimeAsync(step);
      });
    }
  };

  const ticks = () =>
    globalThis.__supabaseMock.rpc.mock.calls.filter(([name]: unknown[]) => name === "tick");

  it("keeps ticking through a live question, not only once its deadline is past", async () => {
    await withFakeTimers(async () => {
      globalThis.__supabaseMock = supabaseMock();
      renderMatch({
        board: {
          phase: "call",
          serverNow: new Date().toISOString(),
          phaseDeadline: new Date(Date.now() + 12_000).toISOString(),
        },
      });

      await advance(9_000);

      expect(ticks().length).toBeGreaterThanOrEqual(3);
    });
  });

  it("stops once the match is over, so a finished board is not polled forever", async () => {
    await withFakeTimers(async () => {
      globalThis.__supabaseMock = supabaseMock();
      renderMatch({
        board: { phase: "complete", serverNow: new Date().toISOString(), phaseDeadline: null },
      });

      await advance(9_000);

      expect(ticks()).toHaveLength(0);
    });
  });
});
