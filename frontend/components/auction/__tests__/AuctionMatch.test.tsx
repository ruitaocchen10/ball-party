import { act, fireEvent, screen, waitFor, within } from "@testing-library/react";
import userEvent from "@testing-library/user-event";
import { describe, expect, it, vi } from "vitest";

vi.mock("@/components/game-runtime/PostGameNavigation", () => ({
  PostGameNavigation: () => null,
}));

import { AuctionMatch } from "@/components/auction/AuctionMatch";
import { LOT_REVEAL_MS } from "@/lib/auction/useLotReveal";
import { MATCH, bid, board, lot, players, standing, turn } from "@/test/factories";
import { renderMatch } from "@/test/render";

/**
 * What the match screen does, asserted through what a player can see and reach.
 *
 * The four phases are the spine of all of it: lot_preview and sold are timer-off
 * and shared by everybody, bidding is one player's turn and everyone else's
 * wait. The component derives the viewer's phase from the shared one plus the
 * seat on the clock, and almost every rule below follows from that.
 */

const raiseButtons = () =>
  screen.getAllByRole("button", { name: /^\+\$/ }) as HTMLButtonElement[];
const customButton = () => screen.getByRole("button", { name: "Custom" }) as HTMLButtonElement;

/** The same mount renderMatch() makes, for the tests that re-render in place. */
const matchWith = (over: Partial<Parameters<typeof AuctionMatch>[0]["initial"]>) => (
  <AuctionMatch
    matchId={MATCH}
    viewerId="u0"
    roomCode="ABCD"
    initial={{
      turn: turn("bidding", { turnSeat: 0 }),
      serverNow: new Date().toISOString(),
      lots: board(),
      players: players(),
      bids: [],
      standings: [],
      format: null,
      ...over,
    }}
  />
);
describe("the four phases", () => {
  it("keeps a board cell for every turn lot, including undealt lots", () => {
    renderMatch({ turn: turn("bidding", { lotCount: 40, currentLot: 2, turnSeat: 0 }) });

    const strip = screen.getByRole("list", { name: "Auction board" });
    expect(within(strip).getAllByRole("listitem")).toHaveLength(40);
    expect(within(strip).getByLabelText("Lot 40, not yet dealt")).toBeInTheDocument();
  });

  it("records a settled lot's face, slot, price, winner, and abbreviated name in the board", () => {
    renderMatch({
      turn: turn("bidding", { currentLot: 2, turnSeat: 0 }),
      lots: board([{ winner_id: "u1", slot: "RB", price: 0 }]),
    });

    const strip = screen.getByRole("list", { name: "Auction board" });
    expect(within(strip).getByLabelText("Lot 1, Saquon Barkley, RB, $0, won by Ben")).toHaveTextContent(
      "S. Barkley",
    );
  });

  it("records an unsold lot without inventing a price or winner", () => {
    renderMatch({ turn: turn("bidding", { currentLot: 2, turnSeat: 0 }) });

    expect(screen.getByLabelText("Lot 1, Saquon Barkley, unfilled, no price, no winner")).toBeInTheDocument();
  });

  it("marks and smoothly scrolls the live board cell without naming undealt players", () => {
    renderMatch({
      turn: turn("sold", { currentLot: 3 }),
      lots: board([
        { winner_id: "u0", slot: "RB", price: 3 },
        { winner_id: "u1", slot: "QB", price: 4 },
        {},
        { display_name: "Undealt Player" },
      ]),
    });

    expect(screen.getByRole("listitem", { current: "step" })).toHaveTextContent(/Lot 3\/? 4Sold/);
    expect(Element.prototype.scrollIntoView).toHaveBeenCalledExactlyOnceWith({
      behavior: "smooth",
      inline: "center",
      block: "nearest",
    });
    expect(screen.queryByText("Undealt Player")).not.toBeInTheDocument();
  });

  it("keeps the compact board treatment for a season lot", () => {
    renderMatch({
      turn: turn("bidding", { currentLot: 2, turnSeat: 0 }),
      lots: board([{ winner_id: "u1", slot: "RB", price: 4, week: null, opponent: null }]),
    });

    expect(screen.getByLabelText("Lot 1, Saquon Barkley, RB, $4, won by Ben")).toHaveTextContent("S. Barkley");
  });

  it("renders every repeated roster slot from the dealt format", () => {
    renderMatch({
      turn: turn("sold"),
      format: {
        scoringMode: "weekly",
        rosterPreset: "deep",
        qbSlots: 2,
        rbSlots: 2,
        wrSlots: 3,
        teSlots: 1,
        flexSlots: 2,
        purse: 50,
        seasonFrom: 2010,
        seasonTo: 2025,
      },
      lots: board([
        { winner_id: "u0", slot: "QB", display_name: "Patrick Mahomes", points: 35.9, price: 5 },
        { winner_id: "u0", slot: "QB", display_name: "Lamar Jackson", points: 31.4, price: 4 },
      ]),
    });

    expect(screen.getAllByLabelText(/^QB [12] slot,/)).toHaveLength(8);
    expect(screen.getByLabelText("QB 2 slot, Lamar Jackson, 31.4 points")).toBeInTheDocument();
  });

  it("omits weekly-only copy for a season-total lot", () => {
    renderMatch({
      turn: turn("lot_preview"),
      format: {
        scoringMode: "season_total",
        rosterPreset: "standard",
        qbSlots: 1,
        rbSlots: 1,
        wrSlots: 1,
        teSlots: 1,
        flexSlots: 1,
        purse: 20,
        seasonFrom: 2010,
        seasonTo: 2025,
      },
      lots: board([{ season: 2018, team: "NYG", week: null, opponent: null }]),
    });

    expect(screen.getByLabelText("2018 season, NYG")).toBeInTheDocument();
    expect(screen.queryByText(/Week|vs /i)).not.toBeInTheDocument();
  });

  it("names the lot but opens no controls during the shared preview", () => {
    renderMatch({ turn: turn("lot_preview") });

    expect(screen.getByText("Saquon Barkley")).toBeInTheDocument();
    expect(screen.getByText(/Bidding has not started/i)).toBeInTheDocument();
    for (const button of raiseButtons()) expect(button).toBeDisabled();
    expect(customButton()).toBeDisabled();
  });

  it("enables the controls and says whose turn it is when the viewer is on the clock", () => {
    renderMatch({ turn: turn("bidding", { turnSeat: 0 }) });

    expect(screen.getByText("Your turn")).toBeInTheDocument();
    for (const button of raiseButtons()) expect(button).toBeEnabled();
    expect(screen.getByRole("button", { name: "Pass" })).toBeInTheDocument();
  });

  it("names the deciding player and offers nothing to press while waiting", () => {
    renderMatch({ turn: turn("bidding", { turnSeat: 1 }) });

    expect(screen.getByText(/Ben is deciding/)).toBeInTheDocument();
    for (const button of raiseButtons()) expect(button).toBeDisabled();
    expect(screen.getByRole("button", { name: "Pass" })).toBeDisabled();
  });

  it("flips the concealed points surface into a points-only reveal", () => {
    renderMatch({
      turn: turn("sold"),
      lots: board([{ winner_id: "u1", price: 12, slot: "RB", points: 23.4 }]),
    });

    const revealed = screen.getByRole("region", { name: "The lot" });
    expect(within(revealed).getByText("23.4")).toBeInTheDocument();
    expect(within(revealed).getByText("$12")).toBeInTheDocument();
    expect(within(revealed).getByText("Ben")).toBeInTheDocument();
    expect(within(revealed).getByText("23.4").closest("[aria-hidden='true']")).not.toBeNull();
    expect(screen.getAllByRole("status")).toHaveLength(1);
    expect(screen.getByRole("status")).toHaveTextContent("Saquon Barkley sold to Ben for $12. It reveals 23.4 fantasy points.");
  });

  it("renders a three-digit season score without clipping it", () => {
    renderMatch({
      turn: turn("sold"),
      format: {
        scoringMode: "season_total",
        rosterPreset: "standard",
        qbSlots: 1,
        rbSlots: 1,
        wrSlots: 1,
        teSlots: 1,
        flexSlots: 1,
        purse: 20,
        seasonFrom: 2010,
        seasonTo: 2025,
      },
      lots: board([{ week: null, opponent: null, winner_id: "u1", price: 12, slot: "RB", points: 312.4 }]),
    });

    expect(screen.getByRole("region", { name: "The lot" })).toHaveTextContent("312.4");
  });

  it("shows no resolved lot outside the sold phase, so a stale reveal cannot linger", () => {
    renderMatch({
      turn: turn("lot_preview", { currentLot: 2 }),
      lots: board([{ winner_id: "u1", price: 12, slot: "RB", points: 23.4 }]),
    });

    expect(
      within(screen.getByRole("region", { name: "The lot" })).queryByText("23.4"),
    ).not.toBeInTheDocument();
    // Mounted but silent. The region has to outlive the reveal it announces:
    // a live region created with its text already in it may never be read.
    expect(screen.getByRole("status")).toBeEmptyDOMElement();
  });
});

describe("the clock", () => {
  it("reads out the seconds remaining as well as drawing the bar", async () => {
    renderMatch({ turn: turn("bidding", { turnSeat: 0, deadlineMs: 7_400 }) });

    // The visible clock stops half a second short of the real deadline.
    await waitFor(() => expect(screen.getByText("7")).toBeInTheDocument());
    expect(screen.getByRole("timer")).toHaveAccessibleName("7 seconds left");
  });

  it("keeps the urgent treatment for the last three seconds", async () => {
    renderMatch({ turn: turn("bidding", { turnSeat: 0, deadlineMs: 8_000 }) });
    await waitFor(() => expect(screen.getByRole("timer")).toHaveAccessibleName(/7 seconds/));
    expect(screen.getByText("7").className).not.toMatch(/hidden-text/);
  });

  it("marks the final seconds as urgent", async () => {
    renderMatch({ turn: turn("bidding", { turnSeat: 0, deadlineMs: 2_900 }) });
    await waitFor(() => expect(screen.getByText(/^2\.\d$/)).toBeInTheDocument());
    expect(screen.getByText(/^2\.\d$/).className).toMatch(/hidden-text/);
  });

  it("does not call a timer-off phase urgent, however little time is left", async () => {
    renderMatch({ turn: turn("sold", { deadlineMs: 300 }) });
    const clock = screen.getByRole("region", { name: "Clock" });
    await waitFor(() => expect(within(clock).getByText(/^0\.\d$/)).toBeInTheDocument());
    expect(within(clock).getByText(/^0\.\d$/).className).not.toMatch(/hidden-text/);
  });

  it("announces only the countdown milestones from a polite live region", async () => {
    const { rerender } = renderMatch({ turn: turn("bidding", { turnSeat: 0, deadlineMs: 10_400 }) });
    await waitFor(() => expect(document.querySelector("[aria-live='polite']")).toHaveTextContent("10 seconds left"));

    rerender(matchWith({ turn: turn("bidding", { turnSeat: 0, deadlineMs: 9_400 }) }));
    await waitFor(() => expect(document.querySelector("[aria-live='polite']")).toBeEmptyDOMElement());
  });
});

describe("the status line", () => {
  it("says which slot a win would fill when the viewer may act", () => {
    renderMatch({ turn: turn("bidding", { turnSeat: 0 }) });
    expect(screen.getByText(/A win fills your open RB/)).toBeInTheDocument();
  });

  it("names the blocking rule when the viewer has no open slot", () => {
    renderMatch({
      turn: turn("bidding", { turnSeat: 0 }),
      lots: [
        lot({ seq: 1, position: "RB" }),
        lot({ seq: 2, position: "RB", winner_id: "u0", slot: "RB", points: 10 }),
      ],
    });
    expect(screen.getByText("Your RB slots are full.")).toBeInTheDocument();
    for (const button of raiseButtons()) expect(button).toBeDisabled();
  });

  it("allows each configured slot before explaining that a deep position is full", () => {
    renderMatch({
      turn: turn("bidding", { turnSeat: 0 }),
      format: { scoringMode: "weekly", rosterPreset: "deep", qbSlots: 2, rbSlots: 2, wrSlots: 3, teSlots: 1, flexSlots: 2, purse: 50, seasonFrom: 2010, seasonTo: 2025 },
      lots: board([
        { position: "QB", winner_id: "u0", slot: "QB", points: 22, price: 2 },
        { position: "QB", winner_id: "u0", slot: "QB", points: 18, price: 1 },
      ]),
    });

    expect(screen.getByText("Your QB slots are full.")).toBeInTheDocument();
  });

  it("replaces the status text with a server rejection without moving the controls", async () => {
    const user = userEvent.setup();
    const { supabase } = renderMatch({ turn: turn("bidding", { turnSeat: 0 }) });
    supabase.rpc.mockResolvedValue({ data: null, error: { message: "bid_not_increasing" } });

    const before = raiseButtons()[0].getBoundingClientRect().top;
    await user.click(raiseButtons()[0]);

    expect(await screen.findByRole("alert")).toHaveTextContent(
      "Your bid must be higher than the current price.",
    );
    expect(raiseButtons()[0].getBoundingClientRect().top).toBe(before);
  });

  it("keeps the line present even with nothing to say, so it reserves its space", () => {
    renderMatch({ turn: turn("lot_preview") });
    expect(screen.getByText(/This player enters the auction/)).toBeInTheDocument();
  });
});

describe("bidding", () => {
  it("submits the shortcut as an exact amount, not an increment", async () => {
    const user = userEvent.setup();
    const { supabase } = renderMatch({
      turn: turn("bidding", { turnSeat: 0 }),
      bids: [bid({ price: 7 })],
    });

    await user.click(screen.getByRole("button", { name: "+$5" }));
    expect(supabase.rpc).toHaveBeenCalledWith("place_bid", {
      p_match_id: MATCH,
      p_amount: 12,
    });
  });

  it("closes a raise the viewer cannot afford", () => {
    renderMatch({
      turn: turn("bidding", { turnSeat: 0 }),
      bids: [bid({ price: 18 })],
      seats: players([{ budget: 19 }]),
    });

    expect(screen.getByRole("button", { name: "+$1" })).toBeEnabled();
    expect(screen.getByRole("button", { name: "+$5" })).toBeDisabled();
    expect(screen.getByText(/You can only raise by \$1/)).toBeInTheDocument();
  });

  it("passes through the pass RPC", async () => {
    const user = userEvent.setup();
    const { supabase } = renderMatch({ turn: turn("bidding", { turnSeat: 0 }) });

    await user.click(screen.getByRole("button", { name: "Pass" }));
    expect(supabase.rpc).toHaveBeenCalledWith("pass_lot", { p_match_id: MATCH });
  });
});

describe("the custom bid", () => {
  const open = async () => {
    const user = userEvent.setup();
    const view = renderMatch({
      turn: turn("bidding", { turnSeat: 0 }),
      bids: [bid({ price: 7 })],
    });
    await user.click(customButton());
    return { user, ...view };
  };

  it("opens prefilled to the minimum legal bid and states both limits", async () => {
    await open();
    const field = screen.getByRole("spinbutton", { name: /custom bid/i });

    expect(field).toHaveValue(8);
    expect(field).toHaveAttribute("min", "8");
    expect(field).toHaveAttribute("max", "20");
    expect(screen.getByText(/Minimum is \$8\. Your maximum is \$20\./)).toBeInTheDocument();
  });

  it("takes focus when it opens", async () => {
    await open();
    expect(screen.getByRole("spinbutton", { name: /custom bid/i })).toHaveFocus();
  });

  it("leaves the market row and the clock visible", async () => {
    await open();
    expect(screen.getByRole("timer")).toBeInTheDocument();
    expect(screen.getAllByText("$7", { exact: false })).not.toHaveLength(0);
  });

  it("refuses an amount below the minimum", async () => {
    const { user } = await open();
    const field = screen.getByRole("spinbutton", { name: /custom bid/i });
    await user.clear(field);
    await user.type(field, "7");

    expect(screen.getByRole("button", { name: /Bid \$7/ })).toBeDisabled();
  });

  it("refuses an amount past the budget", async () => {
    const { user } = await open();
    const field = screen.getByRole("spinbutton", { name: /custom bid/i });
    await user.clear(field);
    await user.type(field, "21");

    expect(screen.getByRole("button", { name: /Bid \$21/ })).toBeDisabled();
  });

  it("refuses a fractional amount before it ever reaches the server", async () => {
    const { user } = await open();
    const field = screen.getByRole("spinbutton", { name: /custom bid/i });
    await user.clear(field);
    await user.type(field, "9.5");

    expect(screen.getByRole("button", { name: /Bid \$9\.5/ })).toBeDisabled();
  });

  it("submits an exact whole-dollar amount", async () => {
    const { user, supabase } = await open();
    const field = screen.getByRole("spinbutton", { name: /custom bid/i });
    await user.clear(field);
    await user.type(field, "13");
    await user.click(screen.getByRole("button", { name: /Bid \$13/ }));

    expect(supabase.rpc).toHaveBeenCalledWith("place_bid", {
      p_match_id: MATCH,
      p_amount: 13,
    });
  });

  it("keeps a server rejection inside the open custom-bid popover", async () => {
    const { user, supabase } = await open();
    supabase.rpc.mockResolvedValue({ data: null, error: { message: "bid_not_increasing" } });

    await user.click(screen.getByRole("button", { name: /Bid \$8/ }));

    expect(await within(screen.getByRole("dialog")).findByRole("alert")).toHaveTextContent(
      "Your bid must be higher than the current price.",
    );
  });

  it("closes on Escape and gives focus back to the control that opened it", async () => {
    const { user } = await open();
    await user.keyboard("{Escape}");

    expect(screen.queryByRole("dialog")).not.toBeInTheDocument();
    expect(customButton()).toHaveFocus();
  });

  it("closes on Cancel and gives focus back too", async () => {
    const { user } = await open();
    await user.click(screen.getByRole("button", { name: "Cancel" }));

    expect(screen.queryByRole("dialog")).not.toBeInTheDocument();
    expect(customButton()).toHaveFocus();
  });
});

describe("the table", () => {
  it("keeps the viewer's seat open and lets other seats disclose independently", async () => {
    const user = userEvent.setup();
    renderMatch({ turn: turn("bidding", { turnSeat: 0 }) });
    const table = screen.getByRole("complementary", { name: "The table" });

    const avaSeat = within(table).getByText("You").closest("details")!;
    const benSeat = within(table).getByText("Ben").closest("details")!;
    const avaDisclosure = avaSeat.querySelector("summary")!;
    const benDisclosure = benSeat.querySelector("summary")!;

    expect(avaSeat).toHaveAttribute("open");
    expect(benSeat).not.toHaveAttribute("open");

    await user.click(benDisclosure);

    expect(benSeat).toHaveAttribute("open");
    expect(avaSeat).toHaveAttribute("open");
  });

  it("states a seat's turn once however the seat is disclosed", async () => {
    const user = userEvent.setup();
    renderMatch({ turn: turn("bidding", { turnSeat: 0 }) });
    const table = screen.getByRole("complementary", { name: "The table" });

    // The viewer is on the clock and their own seat opens by default.
    expect(within(table).getAllByText("On the clock")).toHaveLength(1);

    await user.click(within(table).getByText("You").closest("details")!.querySelector("summary")!);

    expect(within(table).getAllByText("On the clock")).toHaveLength(1);
  });

  it("shows every seat's budget and revealed total", () => {
    renderMatch({
      turn: turn("bidding", { turnSeat: 1 }),
      lots: board([{ winner_id: "u1", slot: "RB", points: 18.5, price: 9 }]),
      seats: players([{}, { budget: 11 }]),
    });

    const table = screen.getByRole("complementary", { name: "The table" });
    expect(within(table).getByText("$11", { exact: false })).toBeInTheDocument();
    expect(within(table).getByLabelText("18.5 points")).toBeInTheDocument();
  });

  it("calls the active bidder and the high bidder separately", () => {
    renderMatch({
      turn: turn("bidding", { turnSeat: 2 }),
      bids: [bid({ user_id: "u1", price: 6 })],
    });

    const table = screen.getByRole("complementary", { name: "The table" });
    expect(within(table).getByText("On the clock")).toBeInTheDocument();
    expect(within(table).getByText("High bid · $6")).toBeInTheDocument();
    expect(within(table).getByText("Ben").closest("details")).toHaveClass("bg-panel/5");
  });

  it("marks a seat that has passed", () => {
    renderMatch({
      turn: turn("bidding", { turnSeat: 0 }),
      bids: [bid({ user_id: "u3", action: "pass", price: null, bid_seq: 1 })],
    });

    expect(
      within(screen.getByRole("complementary", { name: "The table" })).getByText("Passed"),
    ).toBeInTheDocument();
  });

  it("distinguishes an empty roster slot from concealed information", () => {
    renderMatch({ turn: turn("bidding", { turnSeat: 0 }) });

    // Five slots per seat, four seats, none of them filled.
    expect(screen.getAllByLabelText(/slot, empty$/)).toHaveLength(20);
  });

  it("shows what a filled slot holds", () => {
    renderMatch({
      turn: turn("bidding", { turnSeat: 1 }),
      lots: board([{ winner_id: "u0", slot: "RB", points: 18.5, price: 9 }]),
    });

    expect(screen.getAllByLabelText(/slot, empty$/)).toHaveLength(19);
    expect(
      screen.getByLabelText("RB slot, Saquon Barkley, 18.5 points"),
    ).toBeInTheDocument();
  });

  it("highlights the winner and the slot the lot went into, during sold", () => {
    renderMatch({
      turn: turn("sold"),
      lots: board([{ winner_id: "u1", slot: "RB", points: 18.5, price: 9 }]),
    });

    const table = screen.getByRole("complementary", { name: "The table" });
    const seat = within(table).getByText("Ben").closest("details")!;
    expect(seat.className).toMatch(/animate-sold-once/);
    // The animation is behind motion-safe, so the ring survives reduced motion.
    expect(seat.className).toMatch(/motion-safe:/);
    expect(screen.getByText("Sold to")).toBeInTheDocument();
    expect(within(screen.getByRole("region", { name: "The lot" })).getByText("Ben")).toBeInTheDocument();
    expect(within(screen.getByRole("region", { name: "The lot" })).getByText("$9")).toBeInTheDocument();
    expect(screen.getByLabelText("RB slot, Saquon Barkley, 18.5 points").closest("div")!.className).toMatch(/animate-player-to-roster/);
  });
});

describe("the shape of the screen", () => {
  it("gives a spectator no controls at all", () => {
    renderMatch({ turn: turn("bidding", { turnSeat: 0 }), viewerId: null });

    expect(screen.getByText(/You're watching this one/)).toBeInTheDocument();
    expect(screen.queryByRole("button", { name: "Custom" })).not.toBeInTheDocument();
  });

  it("names the three regions so they can be found without looking at the layout", () => {
    renderMatch({ turn: turn("bidding", { turnSeat: 0 }) });

    expect(screen.getByRole("region", { name: "The controls" })).toBeInTheDocument();
    expect(screen.getByRole("region", { name: "The lot" })).toBeInTheDocument();
    expect(screen.getByRole("complementary", { name: "The table" })).toBeInTheDocument();
  });

  it.each(["lot_preview", "bidding", "sold"] as const)(
    "keeps Pass in the bid panel during %s, so the control cannot move under a thumb",
    (phase) => {
      renderMatch({ turn: turn(phase, { turnSeat: 0 }) });

      const controls = screen.getByRole("region", { name: "Bid controls" });
      expect(within(controls).getByRole("button", { name: "Pass" })).toBeInTheDocument();
    },
  );

  it("keeps Pass in the bid panel while another seat decides", () => {
    renderMatch({ turn: turn("bidding", { turnSeat: 1 }) });

    const controls = screen.getByRole("region", { name: "Bid controls" });
    expect(within(controls).getByRole("button", { name: "Pass" })).toBeInTheDocument();
  });

  it("gives Pass the same full-size control affordance as a bid action", () => {
    renderMatch({ turn: turn("bidding", { turnSeat: 0 }) });

    expect(screen.getByRole("button", { name: "Pass" })).toHaveClass("min-h-12");
  });

  it("runs with no app chrome throughout, live or final, so no mis-tap ever navigates out of the match", () => {
    renderMatch({ turn: turn("bidding", { turnSeat: 0 }) });

    expect(screen.queryByRole("link", { name: "Ball Party" })).not.toBeInTheDocument();
  });

  it("keeps the final standings, revealing a roster once its row is expanded", async () => {
    const user = userEvent.setup();
    renderMatch({
      turn: turn("sold", { currentLot: 5, lotCount: 4 }),
      lots: board([
        { winner_id: "u0", slot: "RB", points: 20, price: 5 },
        { winner_id: "u1", slot: "QB", points: 10, price: 3 },
      ]),
      standings: [
        standing({ user_id: "u0", placement: 1, raw_score: 20 }),
        standing({ user_id: "u1", placement: 2, raw_score: 10 }),
      ],
    });

    expect(screen.getByText("Ava wins")).toBeInTheDocument();
    expect(screen.getByText(/Saquon Barkley/)).not.toBeVisible();

    await user.click(within(screen.getAllByRole("listitem")[0]).getByText("Ava").closest("summary")!);
    expect(screen.getByText(/Saquon Barkley/)).toBeVisible();
    // The final screen stays chrome-free too, same as the other two games'
    // own endings (components/game-runtime/PostGameControls is the way
    // back, not app navigation reappearing around it).
    expect(screen.queryByRole("link", { name: "Ball Party" })).not.toBeInTheDocument();
  });
});


describe("pausing", () => {
  it("gives only the host a pause control", () => {
    renderMatch({ turn: turn("bidding", { turnSeat: 0 }), isHost: false });
    expect(screen.queryByRole("button", { name: "Pause" })).not.toBeInTheDocument();

    renderMatch({ turn: turn("bidding", { turnSeat: 0 }), isHost: true });
    expect(screen.getByRole("button", { name: "Pause" })).toBeInTheDocument();
  });

  it("asks the server to pause the match", async () => {
    const user = userEvent.setup();
    const { supabase } = renderMatch({ turn: turn("bidding", { turnSeat: 0 }), isHost: true });

    await user.click(screen.getByRole("button", { name: "Pause" }));
    expect(supabase.rpc).toHaveBeenCalledWith("pause_match", { p_match_id: MATCH });
  });

  it("offers Resume instead once the match is paused, and asks the server to resume it", async () => {
    const user = userEvent.setup();
    const { supabase } = renderMatch({
      turn: turn("bidding", { turnSeat: 0 }),
      isHost: true,
      paused: true,
    });

    expect(screen.queryByRole("button", { name: "Pause" })).not.toBeInTheDocument();
    await user.click(screen.getByRole("button", { name: "Resume" }));
    expect(supabase.rpc).toHaveBeenCalledWith("resume_match", { p_match_id: MATCH });
  });

  it("surfaces a rejection from the server", async () => {
    const user = userEvent.setup();
    const { supabase } = renderMatch({ turn: turn("bidding", { turnSeat: 0 }), isHost: true });
    supabase.rpc.mockResolvedValue({ data: null, error: { message: "not_host" } });

    await user.click(screen.getByRole("button", { name: "Pause" }));
    expect(await screen.findByRole("alert")).toHaveTextContent("Only the host can pause the game.");
  });

  it("shows everybody the paused banner and disables bidding, even for the player on the clock", () => {
    renderMatch({ turn: turn("bidding", { turnSeat: 0 }), paused: true });

    expect(screen.getByText("Paused")).toBeInTheDocument();
    expect(screen.getAllByText(/The host paused the game/).length).toBeGreaterThan(0);
    for (const button of raiseButtons()) expect(button).toBeDisabled();
    expect(screen.getByRole("button", { name: "Pass" })).toBeDisabled();
  });
});

/**
 * The screen's two self-healing loops, both added after a playtest where three
 * lots in one game took 81s, 127s and 271s — one of them with no player actions
 * at all. Expiry used to fire once per state and latch, so a single no-op meant
 * nobody ever asked again and the auction waited on the janitor. Realtime had
 * the same shape of bug: events were applied and never checked.
 */
describe("keeping the screen honest", () => {
  // Date has to be faked as well as the interval: the component derives `now`
  // from Date.now() plus its measured server offset, so a fake interval driving
  // a real clock advances the ticks without advancing the time they read.
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

  /** Lets the mount-time subscribe (and its one refetch) settle. */
  const settle = async () => {
    await act(async () => {
      await vi.advanceTimersByTimeAsync(50);
    });
  };

  /**
   * Advances in separate flushes rather than one big jump. React batches every
   * state update inside a single act() into one render, so advancing four
   * seconds at once would show the effect exactly one value of `now` — which
   * says nothing about behaviour that is defined per tick.
   */
  const advance = async (ms: number, step = 500) => {
    for (let elapsed = 0; elapsed < ms; elapsed += step) {
      await act(async () => {
        await vi.advanceTimersByTimeAsync(step);
      });
    }
  };

  const expiries = (supabase: { rpc: { mock: { calls: unknown[][] } } }) =>
    supabase.rpc.mock.calls.filter(([fn]) => fn === "expire_turn");

  it("keeps asking the server to expire a passed deadline rather than asking once", async () => {
    await withFakeTimers(async () => {
      const { supabase } = renderMatch({ turn: turn("lot_preview", { deadlineMs: -200 }) });
      await advance(4_000);
      // One attempt per RETRY_MS while the deadline stays past.
      expect(expiries(supabase).length).toBeGreaterThan(1);
    });
  });

  it("never asks on behalf of the player on the clock, who is the one client that cannot be trusted with it", async () => {
    await withFakeTimers(async () => {
      const { supabase } = renderMatch({
        turn: turn("bidding", { turnSeat: 0, deadlineMs: -2_000 }),
      });
      await advance(4_000);
      expect(expiries(supabase)).toHaveLength(0);
    });
  });

  it("still asks while waiting on somebody else's turn", async () => {
    await withFakeTimers(async () => {
      const { supabase } = renderMatch({
        turn: turn("bidding", { turnSeat: 1, deadlineMs: -2_000 }),
      });
      await advance(4_000);
      expect(expiries(supabase).length).toBeGreaterThan(0);
    });
  });

  it("re-reads the board once a deadline is far enough past to distrust the screen", async () => {
    await withFakeTimers(async () => {
      const { supabase } = renderMatch({ turn: turn("sold", { deadlineMs: -100 }) });
      await settle();
      supabase.from.mockClear();
      await advance(6_000);
      expect(supabase.from.mock.calls.map(([table]) => table)).toContain("auction_lots");
    });
  });

  it("leaves a healthy screen alone", async () => {
    await withFakeTimers(async () => {
      const { supabase } = renderMatch({ turn: turn("bidding", { turnSeat: 1, deadlineMs: 20_000 }) });
      await settle();
      supabase.from.mockClear();
      await advance(3_000);
      expect(supabase.from).not.toHaveBeenCalled();
      expect(expiries(supabase)).toHaveLength(0);
    });
  });

  it("re-reads the board when the tab comes back, since a backgrounded clock barely ran", async () => {
    const { supabase } = renderMatch({ turn: turn("bidding", { turnSeat: 1 }) });
    await waitFor(() => expect(supabase.from).toHaveBeenCalled());
    supabase.from.mockClear();

    await act(async () => {
      document.dispatchEvent(new Event("visibilitychange"));
    });
    expect(supabase.from.mock.calls.map(([table]) => table)).toContain("auction_players");
  });

  it("re-reads the board when the realtime channel joins, which is when missed events are known to exist", async () => {
    // The mock reports SUBSCRIBED as soon as the component subscribes.
    const { supabase } = renderMatch({ turn: turn("lot_preview") });
    await waitFor(() =>
      expect(supabase.from.mock.calls.map(([table]) => table)).toContain("auction_bids"),
    );
  });
});

/**
 * The ~2s "revealing" buffer between one lot's player and the next
 * (useLotReveal), mirroring sabotage draft's own turn-spin reveal. `lots` is
 * internal state seeded once from `initial` and already holds every lot's
 * real identity (see board()); the turn only ever moves via a real RPC round
 * trip, so a lot change here comes from re-mocking `rpc` and driving it
 * through an existing, already-tested action (passing), the same way the
 * game itself would learn the lot moved on.
 */
describe("the lot's suspense reveal", () => {
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

  it("shows a lot already underway at mount immediately, with no artificial wait", () => {
    renderMatch({ turn: turn("lot_preview", { currentLot: 2 }) });
    expect(screen.getByText("Patrick Mahomes")).toBeInTheDocument();
  });

  it("conceals the next lot's player until the reveal delay elapses, then shows it", async () => {
    await withFakeTimers(async () => {
      const { supabase } = renderMatch({ turn: turn("bidding", { turnSeat: 0 }) });
      supabase.rpc.mockImplementation(async (...args: unknown[]) => {
        if (args[0] !== "pass_lot") return { data: null, error: null };
        return {
          data: {
            lot_count: 4,
            current_lot: 2,
            turn_seat: null,
            opener_seat: 0,
            turn_deadline: null,
            phase: "lot_preview",
            phase_deadline: new Date(Date.now() + 5_000).toISOString(),
            server_now: new Date().toISOString(),
          },
          error: null,
        };
      });

      expect(screen.getByText("Saquon Barkley")).toBeInTheDocument();

      // A plain fireEvent click plus a zero-length timer advance, not
      // userEvent, whose own internal delay machinery doesn't mix cleanly
      // with fake timers here — drains the click handler's promise chain.
      await act(async () => {
        fireEvent.click(screen.getByRole("button", { name: "Pass" }));
        await vi.advanceTimersByTimeAsync(0);
      });

      expect(screen.getByText("Revealing…")).toBeInTheDocument();
      // The reel has the answer as its final, off-screen row so it can settle
      // onto it. It remains inside aria-hidden animated artwork until the
      // suspense delay completes; the visible player card is still concealed.
      expect(screen.getByText("Patrick Mahomes").closest("[aria-hidden='true']")).not.toBeNull();

      await advance(LOT_REVEAL_MS - 500);
      expect(screen.getByText("Patrick Mahomes").closest("[aria-hidden='true']")).not.toBeNull();

      await advance(600);
      expect(screen.getByText("Patrick Mahomes")).toBeInTheDocument();
    });
  });
});
