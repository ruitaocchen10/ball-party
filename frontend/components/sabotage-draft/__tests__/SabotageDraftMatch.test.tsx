import { act, fireEvent, render, screen } from "@testing-library/react";
import userEvent from "@testing-library/user-event";
import { beforeEach, describe, expect, it, vi } from "vitest";

import { SabotageDraftMatch } from "@/components/sabotage-draft/SabotageDraftMatch";
import { TURN_REVEAL_MS } from "@/lib/sabotage-draft/useTurnReveal";
import { MATCH, supabaseMock } from "@/test/factories";

const PLAYERS = [
  { match_id: MATCH, user_id: "u0", seat: 0, absent: false, display_name: "Ava" },
  { match_id: MATCH, user_id: "u1", seat: 1, absent: false, display_name: "Ben" },
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
  spins?: { match_id: string; round_number: number; user_id: string; franchise_code: string }[];
  board?: typeof BOARD;
} = {}) {
  return render(
    <SabotageDraftMatch
      matchId={MATCH}
      viewerId={over.viewerId ?? "u0"}
      isHost={over.isHost ?? false}
      paused={over.paused ?? false}
      initial={{
        board: over.board ?? BOARD,
        players: PLAYERS,
        spins: over.spins ?? [],
        picks: [],
        statuses: [],
        hits: [],
        guesses: [],
        passes: [],
        decisions: [],
        standings: [],
        tiebreaks: [],
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
    renderMatch({ board: { ...BOARD, turn_deadline: new Date(Date.now() + 2_500).toISOString() } });
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
