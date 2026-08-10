import { screen, waitFor, within } from "@testing-library/react";
import userEvent from "@testing-library/user-event";
import { describe, expect, it } from "vitest";

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
describe("the four phases", () => {
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
    expect(screen.queryByRole("button", { name: "Pass" })).not.toBeInTheDocument();
  });

  it("reveals the points and the price during the sold acknowledgement", () => {
    renderMatch({
      turn: turn("sold"),
      lots: board([{ winner_id: "u1", price: 12, slot: "RB", points: 23.4 }]),
    });

    const revealed = screen.getByRole("region", { name: /Lot 1, revealed/i });
    expect(within(revealed).getByText("23.4")).toBeInTheDocument();
    expect(within(revealed).getByText("$12")).toBeInTheDocument();
    expect(within(revealed).getByText("Ben")).toBeInTheDocument();
  });

  it("shows no resolved lot outside the sold phase, so a stale reveal cannot linger", () => {
    renderMatch({
      turn: turn("lot_preview", { currentLot: 2 }),
      lots: board([{ winner_id: "u1", price: 12, slot: "RB", points: 23.4 }]),
    });

    expect(screen.queryByRole("region", { name: /revealed/i })).not.toBeInTheDocument();
  });
});

describe("the clock", () => {
  it("reads out the seconds remaining as well as drawing the bar", async () => {
    renderMatch({ turn: turn("bidding", { turnSeat: 0, deadlineMs: 7_400 }) });

    // The visible clock stops half a second short of the real deadline.
    await waitFor(() => expect(screen.getByText("7s")).toBeInTheDocument());
    expect(screen.getByRole("timer")).toHaveAccessibleName("7 seconds left");
  });

  it("keeps the urgent treatment for the last three seconds", async () => {
    renderMatch({ turn: turn("bidding", { turnSeat: 0, deadlineMs: 8_000 }) });
    await waitFor(() => expect(screen.getByRole("timer")).toHaveAccessibleName(/7 seconds/));
    expect(screen.getByText("7s").className).not.toMatch(/hidden-text/);
  });

  it("marks the final seconds as urgent", async () => {
    renderMatch({ turn: turn("bidding", { turnSeat: 0, deadlineMs: 2_900 }) });
    await waitFor(() => expect(screen.getByText("3s")).toBeInTheDocument());
    expect(screen.getByText("3s").className).toMatch(/hidden-text/);
  });

  it("does not call a timer-off phase urgent, however little time is left", async () => {
    renderMatch({ turn: turn("sold", { deadlineMs: 300 }) });
    await waitFor(() => expect(screen.getByText("1s")).toBeInTheDocument());
    expect(screen.getByText("1s").className).not.toMatch(/hidden-text/);
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
    expect(screen.getByText(/no open slot for this position/i)).toBeInTheDocument();
    for (const button of raiseButtons()) expect(button).toBeDisabled();
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
      bids: [bid({ price: 48 })],
      seats: players([{ budget: 49 }]),
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
    expect(field).toHaveAttribute("max", "50");
    expect(screen.getByText(/Minimum is \$8\. Your maximum is \$50\./)).toBeInTheDocument();
  });

  it("takes focus when it opens", async () => {
    await open();
    expect(screen.getByRole("spinbutton", { name: /custom bid/i })).toHaveFocus();
  });

  it("leaves the market row and the clock visible", async () => {
    await open();
    expect(screen.getByRole("timer")).toBeInTheDocument();
    expect(screen.getByText("$7", { exact: false })).toBeInTheDocument();
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
    await user.type(field, "51");

    expect(screen.getByRole("button", { name: /Bid \$51/ })).toBeDisabled();
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
    await user.type(field, "23");
    await user.click(screen.getByRole("button", { name: /Bid \$23/ }));

    expect(supabase.rpc).toHaveBeenCalledWith("place_bid", {
      p_match_id: MATCH,
      p_amount: 23,
    });
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
  it("shows every seat's budget and revealed total", () => {
    renderMatch({
      turn: turn("bidding", { turnSeat: 1 }),
      lots: board([{ winner_id: "u1", slot: "RB", points: 18.5, price: 9 }]),
      seats: players([{}, { budget: 41 }]),
    });

    const table = screen.getByRole("complementary", { name: "The table" });
    expect(within(table).getByText("$41", { exact: false })).toBeInTheDocument();
    expect(within(table).getByText(/18\.5 pts/)).toBeInTheDocument();
  });

  it("calls the active bidder and the high bidder separately", () => {
    renderMatch({
      turn: turn("bidding", { turnSeat: 2 }),
      bids: [bid({ user_id: "u1", price: 6 })],
    });

    const table = screen.getByRole("complementary", { name: "The table" });
    expect(within(table).getByText("on the clock")).toBeInTheDocument();
    expect(within(table).getByText("high bid")).toBeInTheDocument();
  });

  it("marks a seat that has passed", () => {
    renderMatch({
      turn: turn("bidding", { turnSeat: 0 }),
      bids: [bid({ user_id: "u3", action: "pass", price: null, bid_seq: 1 })],
    });

    expect(
      within(screen.getByRole("complementary", { name: "The table" })).getByText("passed"),
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
    const seat = within(table).getByText("Ben").closest("li")!;
    expect(seat.className).toMatch(/animate-sold-once/);
    // The animation is behind motion-safe, so the ring survives reduced motion.
    expect(seat.className).toMatch(/motion-safe:/);
    expect(seat.className).toMatch(/border-panel/);
  });
});

describe("the shape of the screen", () => {
  it("gives a spectator no controls at all", () => {
    renderMatch({ turn: turn("bidding", { turnSeat: 0 }), viewerId: null });

    expect(screen.getByText(/You're watching this one/)).toBeInTheDocument();
    expect(screen.queryByRole("button", { name: "Custom" })).not.toBeInTheDocument();
  });

  it("names the two regions so they can be found without looking at the layout", () => {
    renderMatch({ turn: turn("bidding", { turnSeat: 0 }) });

    expect(screen.getByRole("region", { name: "The lot" })).toBeInTheDocument();
    expect(screen.getByRole("complementary", { name: "The table" })).toBeInTheDocument();
  });

  it("says how many more shots at this slot are coming", () => {
    renderMatch({ turn: turn("bidding", { turnSeat: 0 }) });
    expect(screen.getByText(/RB 1 left/)).toBeInTheDocument();
  });

  it("keeps the final standings and every roster once the board runs out", () => {
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
    expect(screen.getByText(/Saquon Barkley/)).toBeInTheDocument();
  });
});
