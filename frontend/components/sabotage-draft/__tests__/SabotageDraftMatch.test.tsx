import { act, fireEvent, render, screen, within } from "@testing-library/react";
import userEvent from "@testing-library/user-event";
import { beforeEach, describe, expect, it, vi } from "vitest";

vi.mock("@/components/game-runtime/PostGameNavigation", () => ({
  PostGameNavigation: () => null,
}));

import { SabotageDraftMatch } from "@/components/sabotage-draft/SabotageDraftMatch";
import { TURN_REVEAL_MS } from "@/lib/sabotage-draft/useTurnReveal";
import { MATCH, supabaseMock } from "@/test/factories";

const PLAYERS = [
  { match_id: MATCH, user_id: "u0", seat: 0, absent: false, display_name: "Ava", avatar_url: null },
  { match_id: MATCH, user_id: "u1", seat: 1, absent: false, display_name: "Ben", avatar_url: null },
];

const BOARD: {
  match_id: string;
  round_count: number;
  current_round: number;
  slot: string;
  turn_deadline: string | null;
  server_now: string;
  x_factor_open: boolean;
  active_user_id: string;
} = {
  match_id: MATCH,
  round_count: 14,
  current_round: 1,
  slot: "QB",
  turn_deadline: new Date(Date.now() + 30_000).toISOString(),
  server_now: new Date().toISOString(),
  x_factor_open: false,
  active_user_id: "u0",
};

function renderMatch(over: {
  isHost?: boolean;
  paused?: boolean;
  viewerId?: string;
  roomCode?: string | null;
  spins?: { match_id: string; round_number: number; user_id: string; franchise_code: string }[];
  board?: typeof BOARD;
  picks?: { match_id: string; round_number: number; user_id: string; player_id: string; display_name: string; season: number; by_timeout: boolean; headshot_url: string | null }[];
  statuses?: { match_id: string; round_number: number; user_id: string }[];
  hits?: { match_id: string; round_number: number; target_user_id: string; kind: "respin" | "sabotage" }[];
  guesses?: { match_id: string; round_number: number; user_id: string; target_user_id: string; result: "miss" | "respun" | "sabotaged" | null }[];
  decisions?: { match_id: string; user_id: string; replace_slot: string | null }[];
  standings?: { user_id: string; roster_strength: number; wins: number; losses: number; tiebreak_rank: number }[];
  tiebreaks?: { record_wins: number; bracket_round: number; game_number: number; player_a: string; player_b: string | null; winner_user_id: string; player_a_score: number | null; player_b_score: number | null }[];
  pickAvs?: { user_id: string; round_number: number; av: number }[];
} = {}) {
  return render(
    <SabotageDraftMatch
      matchId={MATCH}
      viewerId={over.viewerId ?? "u0"}
      roomCode={over.roomCode ?? "ABCD"}
      isHost={over.isHost ?? false}
      paused={over.paused ?? false}
      initial={{
        board: over.board ?? BOARD,
        players: PLAYERS,
        spins: over.spins ?? [],
        picks: over.picks ?? [],
        statuses: over.statuses ?? [],
        hits: over.hits ?? [],
        guesses: over.guesses ?? [],
        passes: [],
        decisions: over.decisions ?? [],
        standings: over.standings ?? [],
        tiebreaks: over.tiebreaks ?? [],
        pickAvs: over.pickAvs ?? [],
      }}
    />,
  );
}

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

  it("shows everybody the paused banner", () => {
    renderMatch({ paused: true });
    expect(screen.getByText("Paused")).toBeInTheDocument();
  });
});

/**
 * The ~3s "the system is choosing" buffer between turns (useTurnReveal), and
 * the bug it was written to close alongside: before this, the reel's
 * "resting on the right team" state was only ever a side effect of a CSS
 * animation reaching its last keyframe — never true for a
 * prefers-reduced-motion viewer (or any environment, like this one, that
 * doesn't evaluate CSS animations at all). These tests exercise the actual
 * refetch cycle, not a prop change: `board` is internal state seeded once
 * from `initial` and only ever moves via a real state RPC round trip, so a
 * turn change here comes from re-mocking `rpc`/`from` and driving a refetch
 * through an existing, already-tested action (submitting a pass), the same
 * way the game itself would learn the turn moved on.
 */
describe("the turn's spin reveal", () => {
  const withFakeTimers = async (body: () => Promise<void>) => {
    vi.useFakeTimers({ toFake: ["setTimeout", "clearTimeout"] });
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

  /** A chainable query stub, like factories.ts's own `query()`, but able to
   *  hand back real rows for the tables this suite cares about. */
  function queryReturning(table: string, rows: unknown) {
    const q: Record<string, unknown> = { table };
    for (const method of ["select", "eq", "order", "limit", "maybeSingle", "single"]) q[method] = () => q;
    q.then = (resolve: (value: { data: unknown; error: null }) => unknown) =>
      Promise.resolve({ data: rows, error: null }).then(resolve);
    return q;
  }

  it("shows the first turn's forms immediately, with no artificial wait", async () => {
    globalThis.__supabaseMock = supabaseMock();
    renderMatch({ viewerId: "u0" });
    expect(await screen.findByRole("heading", { name: "Make your hidden pick" })).toBeInTheDocument();
  });

  it("hides this turn's forms behind a spinning placeholder until the buffer elapses, once the active turn actually changes, and then shows the same team the reel settles on", async () => {
    await withFakeTimers(async () => {
      const spins = [
        { match_id: MATCH, round_number: 1, user_id: "u0", franchise_code: "atl" },
        { match_id: MATCH, round_number: 1, user_id: "u1", franchise_code: "buf" },
      ];
      let activeUserId = "u0";
      const client = supabaseMock();
      client.rpc = vi.fn(async (...args: unknown[]) => {
        if (args[0] === "state") return { data: { ...BOARD, active_user_id: activeUserId }, error: null };
        return { data: null, error: null };
      });
      client.from = vi.fn((table: string) => {
        if (table === "sabotage_draft_round_spins") return queryReturning(table, spins);
        if (table === "sabotage_draft_players") {
          return queryReturning(table, PLAYERS.map(p => ({ ...p, profiles: { display_name: p.display_name } })));
        }
        return queryReturning(table, null);
      });
      globalThis.__supabaseMock = client;

      // Seeded directly, not left to the on-mount refetch to fill in: that
      // refetch is a real, unawaited async round trip (through the mocked
      // realtime subscribe), and this suite's synchronous queries below run
      // before it could plausibly have resolved. Matches how the page itself
      // seeds this data server-side anyway (see app/match/[id]/page.tsx).
      renderMatch({ viewerId: "u1", spins });

      // u0's turn, the first this mount ever sees, is already revealed — u1
      // (not on the clock) gets a guess/pass form right away, no wait.
      // A plain synchronous query, not findByRole/waitFor: under fake timers
      // (only setTimeout/clearTimeout faked below) an async query that finds
      // nothing on its first synchronous check falls back to a setTimeout
      // poll that only this suite's own manual `advance` ever fires, so it
      // would hang forever rather than actually wait. Every query in this
      // test is synchronous for the same reason — each one runs at a point
      // this test has already driven the relevant state to, never a point
      // still waiting on one.
      const passButton = screen.getByRole("button", { name: "Pass" });
      expect(screen.queryByText("Spinning…")).not.toBeInTheDocument();

      // The turn actually changes: u1 becomes the active seat. Submitting
      // the pass is just the trigger available in this fixture for a real
      // refetch — same as any other successful action. A plain fireEvent
      // click plus a zero-length timer advance (rather than userEvent, whose
      // own internal delay machinery doesn't mix cleanly with fake timers
      // here) drains the click handler's promise chain -- the RPC call, then
      // refetch's Promise.all of eleven more.
      activeUserId = "u1";
      await act(async () => {
        fireEvent.click(passButton);
        await vi.advanceTimersByTimeAsync(0);
      });

      // Newly on the clock, but still spinning: no pick form yet, and the
      // announcement doesn't claim a team. (The reel's own decoy list does
      // still carry the real team as its last item at this point -- that's
      // the value the animation scrolls to -- but jsdom never runs the CSS
      // that would actually reveal it, so it isn't part of what's asserted
      // here; "Spun the Buffalo Bills" is the one place a viewer is actually
      // told the team, and that's what's checked.)
      expect(screen.getAllByText("Spinning…").length).toBeGreaterThan(0);
      expect(screen.queryByRole("heading", { name: "Make your hidden pick" })).not.toBeInTheDocument();
      expect(screen.queryByText(/Spun the Buffalo Bills/)).not.toBeInTheDocument();

      await advance(TURN_REVEAL_MS - 500);
      expect(screen.queryByRole("heading", { name: "Make your hidden pick" })).not.toBeInTheDocument();

      await advance(600);
      // Revealed: the pick form opens and the announcement names the team --
      // rendered directly from `revealed`, not as a side effect of any CSS
      // animation having played (jsdom never runs one at all). This is the
      // actual resting DOM, not a frame an animation happened to land on.
      expect(screen.getByRole("heading", { name: "Make your hidden pick" })).toBeInTheDocument();
      expect(screen.getByText(/Spun the Buffalo Bills/)).toBeInTheDocument();
    });
  });
});

/**
 * The recap that fills the "Your move" column's spinning window with what
 * the *previous* turn resolved to (TurnResultCard, built from a snapshot the
 * effect in SabotageDraftMatch takes the instant the turn changes), plus the
 * matching flash on that player's row in "Everyone's teams" (RosterBoard's
 * `resolvedHere`). Driven through the same real refetch cycle as "the turn's
 * spin reveal" above, not a prop change — this is the case that matters most
 * to get right: a turn resolving for someone other than the viewer, where
 * `sabotage_draft_picks`' RLS means their pick never reaches this client at
 * all, resolved or not, so the recap has to fall back to the franchise/slot
 * shape instead of a name.
 */
describe("the turn result recap", () => {
  const withFakeTimers = async (body: () => Promise<void>) => {
    vi.useFakeTimers({ toFake: ["setTimeout", "clearTimeout"] });
    try {
      await body();
    } finally {
      vi.useRealTimers();
    }
  };

  function queryReturning(table: string, rows: unknown) {
    const q: Record<string, unknown> = { table };
    for (const method of ["select", "eq", "order", "limit", "maybeSingle", "single"]) q[method] = () => q;
    q.then = (resolve: (value: { data: unknown; error: null }) => unknown) =>
      Promise.resolve({ data: rows, error: null }).then(resolve);
    return q;
  }

  it("recaps someone else's sabotaged turn without their identity, and flashes their roster row", async () => {
    await withFakeTimers(async () => {
      const spins = [
        { match_id: MATCH, round_number: 1, user_id: "u0", franchise_code: "atl" },
        { match_id: MATCH, round_number: 1, user_id: "u1", franchise_code: "buf" },
      ];
      const hits = [{ match_id: MATCH, round_number: 1, target_user_id: "u0", kind: "sabotage" as const }];
      const guesses = [{ match_id: MATCH, round_number: 1, user_id: "u1", target_user_id: "u0", result: "sabotaged" as const }];
      let activeUserId = "u0";
      const client = supabaseMock();
      client.rpc = vi.fn(async (...args: unknown[]) => {
        if (args[0] === "state") return { data: { ...BOARD, active_user_id: activeUserId }, error: null };
        return { data: null, error: null };
      });
      client.from = vi.fn((table: string) => {
        if (table === "sabotage_draft_round_spins") return queryReturning(table, spins);
        if (table === "sabotage_draft_pick_hits") return queryReturning(table, hits);
        if (table === "sabotage_draft_guesses") return queryReturning(table, guesses);
        // No row for u0's own pick — the same shape u1's client actually
        // gets back from a pick it isn't allowed to see, resolved or not.
        if (table === "sabotage_draft_picks") return queryReturning(table, []);
        if (table === "sabotage_draft_players") {
          return queryReturning(table, PLAYERS.map(p => ({ ...p, profiles: { display_name: p.display_name } })));
        }
        return queryReturning(table, null);
      });
      globalThis.__supabaseMock = client;

      renderMatch({ viewerId: "u1", spins });

      const passButton = screen.getByRole("button", { name: "Pass" });
      activeUserId = "u1";
      await act(async () => {
        fireEvent.click(passButton);
        await vi.advanceTimersByTimeAsync(0);
      });

      // Still inside the new turn's spinning window: the recap names the
      // actor and the target, but the target's own pick never surfaces —
      // only the slot and the franchise it came from, the same withheld
      // shape RosterBoard's own concealed rows already use.
      expect(screen.getByText(/Ben sabotaged Ava/)).toBeInTheDocument();
      expect(screen.getByText(/QB.*Atlanta Falcons/)).toBeInTheDocument();

      const roster = within(screen.getByRole("complementary", { name: "Everyone's teams" }));
      const avaRow = roster.getByText("Ava").closest("summary");
      expect(avaRow).toHaveClass("motion-safe:animate-sold-once");
      expect(avaRow).toHaveClass("bg-hidden/15");
    });
  });
});

/**
 * The left column's other half — the countdown replacing what used to be a
 * plain-text `Your pick · 30s` in the page header. A `<section
 * aria-label="Clock">` picks up an implicit `region` role from its
 * accessible name, which is how these tests find it without reaching for
 * test ids.
 */
describe("the turn clock", () => {
  beforeEach(() => {
    globalThis.__supabaseMock = supabaseMock();
  });

  it("counts down without a unit suffix while a turn is in progress", () => {
    renderMatch();
    const clock = screen.getByRole("region", { name: "Clock" });
    expect(clock).toHaveTextContent("30");
    expect(clock).not.toHaveTextContent("30s");
    expect(screen.getByRole("timer")).toBeInTheDocument();
  });

  it("counts down in tenths once fewer than five seconds remain", () => {
    renderMatch({ board: { ...BOARD, turn_deadline: new Date(Date.now() + 4_500).toISOString() } });
    const clock = screen.getByRole("region", { name: "Clock" });
    expect(clock).toHaveTextContent(/\d\.\d/);
  });

  it("shows a dash and an idle bar once nothing is timed", () => {
    renderMatch({ board: { ...BOARD, turn_deadline: null, x_factor_open: false } });
    const clock = screen.getByRole("region", { name: "Clock" });
    expect(clock).toHaveTextContent("—");
    expect(screen.getByRole("timer", { name: "No timer" })).toBeInTheDocument();
  });

  it("turns urgent once three seconds or fewer remain, from the very first render", () => {
    // Anchored to the same instant rather than BOARD's own module-load-time
    // server_now: useMatchClock derives its clock from the offset between
    // the two, so a turn_deadline computed fresh against a server_now
    // captured whenever this file was imported drifts further apart the
    // longer the suite runs before reaching this test -- flaky in exactly
    // the way a boundary this tight (2.5s against a 3s threshold) notices.
    const now = new Date();
    renderMatch({
      board: { ...BOARD, server_now: now.toISOString(), turn_deadline: new Date(now.getTime() + 2_500).toISOString() },
    });
    const clock = screen.getByRole("region", { name: "Clock" });
    expect(clock).toHaveClass("border-hidden");
  });

  it("labels the clock 'Your pick' for the active player", () => {
    renderMatch({ viewerId: "u0" });
    expect(screen.getByRole("region", { name: "Clock" })).toHaveTextContent("Your pick");
  });

  it("labels the clock with the active player's name for everyone else", () => {
    renderMatch({ viewerId: "u1" });
    expect(screen.getByRole("region", { name: "Clock" })).toHaveTextContent("Sabotage Ava");
  });
});

/**
 * Regression coverage for the strip cell that used to spill its own box: a
 * long drafted-player name plus a two-part hit badge stacked past the cell's
 * fixed height with no `overflow-hidden` guard. MatchStrip's shared
 * `StripCell` (components/ui/MatchStrip.tsx) fixes this for both sabotage
 * draft and auction at once, so this asserts the guard actually lands here
 * rather than trusting the shared component was wired in correctly.
 */
describe("the turn strip", () => {
  beforeEach(() => {
    globalThis.__supabaseMock = supabaseMock();
  });

  it("clips a past cell instead of letting a long name and a hit badge overflow it", () => {
    renderMatch({
      viewerId: "u0",
      board: { ...BOARD, current_round: 2 },
      picks: [{ match_id: MATCH, round_number: 1, user_id: "u0", player_id: "p1", display_name: "Christian McCaffrey-Watson Jr.", season: 2019, by_timeout: false, headshot_url: null }],
      statuses: [{ match_id: MATCH, round_number: 1, user_id: "u0" }],
      hits: [
        { match_id: MATCH, round_number: 1, target_user_id: "u0", kind: "respin" },
        { match_id: MATCH, round_number: 1, target_user_id: "u0", kind: "sabotage" },
      ],
    });
    const cell = screen.getByRole("listitem", {
      name: "Round 1, Ava, QB, Christian McCaffrey-Watson Jr. · 2019, Respun · Sabotaged",
    });
    expect(cell).toHaveClass("overflow-hidden");
    expect(screen.getByText("Respun · Sabotaged")).toBeInTheDocument();
  });

  it("leads a revealed past cell with the drafted player, not the drafter, once its identity is visible", () => {
    renderMatch({
      viewerId: "u0",
      board: { ...BOARD, current_round: 2 },
      picks: [{ match_id: MATCH, round_number: 1, user_id: "u0", player_id: "p1", display_name: "Christian McCaffrey", season: 2019, by_timeout: false, headshot_url: null }],
      statuses: [{ match_id: MATCH, round_number: 1, user_id: "u0" }],
    });
    // The drafter's own name moves up to the label a round/slot pair used to
    // occupy; the player they drafted takes over the name/icon spot instead.
    expect(screen.getByText("C. McCaffrey")).toBeInTheDocument();
    expect(screen.getByText("2019")).toBeInTheDocument();
    expect(screen.queryByText("Christian McCaffrey")).not.toBeInTheDocument();
  });

  it("keeps a concealed past cell showing only the drafter and 'Locked'", () => {
    // The server itself is what withholds the row for a still-open round or
    // a round that isn't this viewer's own (see migration 0069) — simulated
    // here the same way: `statuses` says u0 has locked in a pick, but
    // `picks` carries none of it, exactly what u1's own query would get
    // back from Supabase in that situation.
    renderMatch({
      viewerId: "u1",
      board: { ...BOARD, current_round: 2 },
      statuses: [{ match_id: MATCH, round_number: 1, user_id: "u0" }],
    });
    expect(screen.queryByText("C. McCaffrey")).not.toBeInTheDocument();
    expect(screen.getAllByText("Locked").length).toBeGreaterThan(0);
  });
});

/**
 * The season's ending (components/game-runtime/FinalStandings): rank,
 * avatar, record, and a letter grade for every table, each expandable into
 * the roster behind that grade — a photo and a position-relative grade per
 * pick, no raw AV anywhere (lib/sabotage-draft/grades.ts) — plus the same
 * host-drives-the-room navigation the auction and higher-or-lower final
 * screens already offer.
 */
describe("the final screen", () => {
  beforeEach(() => {
    globalThis.__supabaseMock = supabaseMock();
  });

  // 126 and 50 sit nowhere near each other on gradeForTeam's cutoffs on
  // purpose — A- and F, not two grades close enough to blur together in
  // the assertions below.
  const standings = [
    { user_id: "u0", roster_strength: 126, wins: 14, losses: 3, tiebreak_rank: 1 },
    { user_id: "u1", roster_strength: 50, wins: 10, losses: 7, tiebreak_rank: 1 },
  ];

  it("names the winner and ranks the table under them, with each row's record and letter grade", () => {
    renderMatch({ standings });

    expect(screen.getByRole("heading", { name: "Ava wins" })).toBeInTheDocument();
    const rows = screen.getAllByRole("listitem");
    expect(rows[0]).toHaveTextContent("Ava");
    expect(rows[0]).toHaveTextContent("14-3");
    expect(within(rows[0]).getByLabelText("Grade A-")).toBeInTheDocument();
    expect(rows[1]).toHaveTextContent("Ben");
    expect(rows[1]).toHaveTextContent("10-7");
    expect(within(rows[1]).getByLabelText("Grade F")).toBeInTheDocument();
    // Nobody at the table knows what "126 AV" means -- the raw number is gone.
    expect(screen.queryByText(/AV/)).not.toBeInTheDocument();
  });

  it("keeps a table's roster collapsed until expanded, then shows each pick's photo and grade, offense and defense alike", async () => {
    const user = userEvent.setup();
    renderMatch({
      standings,
      picks: [
        { match_id: MATCH, round_number: 1, user_id: "u0", player_id: "p1", display_name: "Patrick Mahomes", season: 2022, by_timeout: false, headshot_url: "https://example.com/mahomes.jpg" },
        // Round 8 is the first defensive slot ROUND_SLOTS deals (OL, right
        // after the seven offensive skill rounds) — this is what regresses
        // if the roster ever goes back to looping the offense-only slice.
        { match_id: MATCH, round_number: 8, user_id: "u0", player_id: "p2", display_name: "Trent Williams", season: 2021, by_timeout: false, headshot_url: null },
      ],
      // QB's own top cutoff is 20 -- 20 AV clears it, a QB A+. OL's own top
      // cutoff is 15 -- 15 AV clears it too, an OL A+. Different position,
      // different scale, same letter -- exactly the point of grading each
      // pick against its own position.
      pickAvs: [
        { user_id: "u0", round_number: 1, av: 20 },
        { user_id: "u0", round_number: 8, av: 15 },
      ],
    });

    expect(screen.getByText(/Patrick Mahomes/)).not.toBeVisible();

    await user.click(screen.getByText("Ava").closest("summary")!);

    const roster = screen.getByText(/Patrick Mahomes/).closest("dl")!;
    expect(screen.getByText(/Patrick Mahomes/)).toBeVisible();
    expect(screen.getByText(/Trent Williams/)).toBeVisible();
    expect(within(roster).getAllByLabelText("Grade A+")).toHaveLength(2);
    // Mahomes has a real headshot; Trent Williams here doesn't -- both
    // still render a portrait (a photo or the onError-style initials chip),
    // but only the one with a real headshot_url renders an actual <img>
    // (decorative, alt="" -- not queryable by role without a live browser's
    // accessibility tree, so this reaches into the DOM directly).
    expect(roster.querySelector("img")).toHaveAttribute("src", "https://example.com/mahomes.jpg");
  });

  it("offers the host a way back to the lobby", () => {
    renderMatch({ standings, isHost: true });

    expect(screen.getByRole("button", { name: /back to lobby/i })).toBeInTheDocument();
  });

  it("turns a tied record's simulated game into a scored playoff matchup", () => {
    renderMatch({
      standings,
      tiebreaks: [{
        record_wins: 10,
        bracket_round: 1,
        game_number: 1,
        player_a: "u0",
        player_b: "u1",
        winner_user_id: "u0",
        player_a_score: 27,
        player_b_score: 20,
      }],
    });

    const bracket = screen.getByRole("heading", { name: "10-7 tiebreak" }).closest("section")!;
    expect(within(bracket).getByText("Final")).toBeInTheDocument();
    expect(within(bracket).getByText("Ava")).toBeInTheDocument();
    expect(within(bracket).getByText("Ben")).toBeInTheDocument();
    expect(within(bracket).getByText("27")).toBeInTheDocument();
    expect(within(bracket).getByText("20")).toBeInTheDocument();
  });
});
