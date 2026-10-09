import { render, screen } from "@testing-library/react";
import userEvent from "@testing-library/user-event";
import { beforeEach, describe, expect, it, vi } from "vitest";

const rpc = vi.fn();
const push = vi.fn();
vi.mock("@/lib/supabase/client", () => ({ createClient: () => ({ rpc }) }));
vi.mock("next/navigation", () => ({ useRouter: () => ({ push }) }));

import { RoomInvitesInbox, type RoomInvite } from "./RoomInvitesInbox";

const invite: RoomInvite = {
  inviteId: "inv-1",
  senderName: "Ava",
  senderUsername: "ava",
  senderAvatarUrl: null,
  selectedGame: "higher_or_lower",
  memberCount: 2,
};

beforeEach(() => {
  rpc.mockReset();
  push.mockReset();
});

describe("RoomInvitesInbox", () => {
  it("renders nothing without invites", () => {
    const { container } = render(<RoomInvitesInbox invites={[]} />);
    expect(container).toBeEmptyDOMElement();
  });

  it("describes the room and accepting navigates into it", async () => {
    const user = userEvent.setup();
    rpc.mockResolvedValue({ data: { code: "BLTZ" }, error: null });
    render(<RoomInvitesInbox invites={[invite]} />);

    expect(screen.getByText("Ava invited you")).toBeInTheDocument();
    expect(screen.getByText("Higher or Lower · 2 of 4 players")).toBeInTheDocument();

    await user.click(screen.getByRole("button", { name: "Join Ava's room" }));
    expect(rpc).toHaveBeenCalledWith("accept_room_invite", { p_invite_id: "inv-1" });
    expect(push).toHaveBeenCalledWith("/lobby/BLTZ");
  });

  it("shows the refusal and stays put when the room can't be joined", async () => {
    const user = userEvent.setup();
    rpc.mockResolvedValue({ data: null, error: { message: "lobby_full" } });
    render(<RoomInvitesInbox invites={[invite]} />);

    await user.click(screen.getByRole("button", { name: "Join Ava's room" }));
    expect(await screen.findByRole("alert")).toHaveTextContent("That room is already full.");
    expect(push).not.toHaveBeenCalled();
  });

  it("declining removes the invite", async () => {
    const user = userEvent.setup();
    rpc.mockResolvedValue({ data: true, error: null });
    render(<RoomInvitesInbox invites={[invite]} />);

    await user.click(screen.getByRole("button", { name: "Decline invite from Ava" }));
    expect(rpc).toHaveBeenCalledWith("decline_room_invite", { p_invite_id: "inv-1" });
    expect(screen.queryByText("Ava invited you")).not.toBeInTheDocument();
  });

  it("warns that joining leaves the current room", () => {
    render(<RoomInvitesInbox invites={[invite]} hasRoom />);
    expect(screen.getByText(/leaves the room you're in/)).toBeInTheDocument();
  });
});
