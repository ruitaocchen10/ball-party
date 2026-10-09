import { render, screen, waitFor } from "@testing-library/react";
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

  describe("live delivery", () => {
    const row = {
      invite_id: "inv-2",
      sender_display_name: "Ben",
      sender_username: "ben",
      sender_avatar_url: null,
      selected_game: null,
      member_count: 1,
    };

    function realtimeClient(rpcResult: unknown) {
      const handlers: Array<() => void> = [];
      let onStatus: ((status: string) => void) | undefined;
      const client = {
        rpc: vi.fn(async () => rpcResult),
        channel: vi.fn(() => client),
        on: (_event: string, filter: { table: string; filter: string }, callback: () => void) => {
          expect(filter).toMatchObject({ table: "room_invites", filter: "recipient_id=eq.viewer-1" });
          handlers.push(callback);
          return client;
        },
        subscribe: (callback: (status: string) => void) => {
          onStatus = callback;
          return client;
        },
        removeChannel: vi.fn(),
      };
      globalThis.__supabaseMock = client as unknown as typeof globalThis.__supabaseMock;
      return { client, handlers, joined: () => onStatus?.("SUBSCRIBED") };
    }

    it("shows an invite that arrives while the page is open", async () => {
      const { client, handlers } = realtimeClient({ data: [row], error: null });
      render(<RoomInvitesInbox invites={[]} viewerId="viewer-1" />);

      await waitFor(() => expect(handlers).toHaveLength(1));
      expect(screen.queryByText("Ben invited you")).not.toBeInTheDocument();

      handlers[0]();
      expect(await screen.findByText("Ben invited you")).toBeInTheDocument();
      expect(client.rpc).toHaveBeenCalledWith("list_room_invites");
    });

    it("re-reads on every (re)subscribe, since an invite sent during a drop makes no event", async () => {
      const { client, joined } = realtimeClient({ data: [row], error: null });
      render(<RoomInvitesInbox invites={[]} viewerId="viewer-1" />);

      await waitFor(() => expect(client.channel).toHaveBeenCalled());
      joined();
      expect(await screen.findByText("Ben invited you")).toBeInTheDocument();
    });

    it("keeps the list when the re-read fails", async () => {
      const { handlers } = realtimeClient({ data: null, error: { message: "boom" } });
      render(<RoomInvitesInbox invites={[invite]} viewerId="viewer-1" />);

      await waitFor(() => expect(handlers).toHaveLength(1));
      handlers[0]();
      await new Promise((resolve) => setTimeout(resolve, 0));
      expect(screen.getByText("Ava invited you")).toBeInTheDocument();
    });

    it("opens no channel for a viewer who cannot have invites", async () => {
      const { client } = realtimeClient({ data: [], error: null });
      render(<RoomInvitesInbox invites={[]} viewerId={null} />);
      await new Promise((resolve) => setTimeout(resolve, 0));
      expect(client.channel).not.toHaveBeenCalled();
    });

    it("closes its channel on unmount", async () => {
      const { client, handlers } = realtimeClient({ data: [], error: null });
      const { unmount } = render(<RoomInvitesInbox invites={[]} viewerId="viewer-1" />);
      await waitFor(() => expect(handlers).toHaveLength(1));
      unmount();
      expect(client.removeChannel).toHaveBeenCalled();
    });
  });
});
