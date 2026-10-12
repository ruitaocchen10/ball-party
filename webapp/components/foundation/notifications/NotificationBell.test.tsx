import { render, screen, waitFor } from "@testing-library/react";
import userEvent from "@testing-library/user-event";
import { beforeEach, describe, expect, it, vi } from "vitest";

const rpc = vi.fn();
const push = vi.fn();
vi.mock("@/lib/supabase/client", () => ({
  createClient: () => ({ rpc, auth: { getUser: async () => ({ data: { user: { id: "me" } } }) } }),
}));
// Behaves like supabase-js where it matters here: a channel is keyed by its name, asking for a
// name that is already open returns that channel, and `.on()` after `.subscribe()` throws.
const openChannels = new Map<string, { subscribed: boolean }>();
vi.mock("@/lib/runtime/realtime/client", () => ({
  createRealtimeClient: async () => ({
    channel: (name: string) => {
      const existing = openChannels.get(name);
      const state = existing ?? { subscribed: false };
      openChannels.set(name, state);
      const channel = {
        on: () => {
          if (state.subscribed) throw new Error(`cannot add \`postgres_changes\` callbacks for realtime:${name} after \`subscribe()\`.`);
          return channel;
        },
        subscribe: () => {
          state.subscribed = true;
          return channel;
        },
        name,
      };
      return channel;
    },
    removeChannel: (channel: { name: string }) => {
      openChannels.delete(channel.name);
    },
  }),
}));
vi.mock("next/navigation", () => ({ useRouter: () => ({ push }) }));

import { NotificationBell } from "./NotificationBell";

const row = (over: Record<string, unknown>) => ({
  item_key: "n:1", kind: "friend_request", state: "pending", actor_id: "u1", actor_username: "ava",
  actor_display_name: "Ava", actor_avatar_url: null, ref_id: "r1", post_id: null, selected_game: null,
  lobby_id: null, member_count: null, reply_count: 1, is_unread: true, sort_at: "2026-11-08T10:00:00Z", ...over,
});

let inbox: ReturnType<typeof row>[] = [];
let unread = 0;

beforeEach(() => {
  openChannels.clear();
  rpc.mockReset();
  push.mockReset();
  inbox = [];
  unread = 0;
  rpc.mockImplementation(async (name: string) => {
    if (name === "list_inbox") return { data: inbox, error: null };
    if (name === "inbox_unread_count") return { data: unread, error: null };
    return { data: true, error: null };
  });
});

describe("NotificationBell", () => {
  it("shows the unread count on the bell", async () => {
    inbox = [row({})];
    unread = 1;
    render(<NotificationBell />);
    expect(await screen.findByRole("button", { name: "Notifications, 1 new" })).toBeInTheDocument();
  });

  it("lists friend requests, take replies and room invites in the panel", async () => {
    const user = userEvent.setup();
    inbox = [
      row({}),
      row({ item_key: "n:2", kind: "take_reply", state: "active", post_id: "p1", ref_id: "t1", reply_count: 3 }),
      row({ item_key: "i:3", kind: "room_invite", ref_id: "inv1", selected_game: "higher_or_lower", member_count: 2, is_unread: true }),
    ];
    unread = 3;
    render(<NotificationBell />);
    await user.click(await screen.findByRole("button", { name: /Notifications/ }));

    expect(screen.getByText("Ava sent you a friend request")).toBeInTheDocument();
    expect(screen.getByText("3 new replies to your take")).toBeInTheDocument();
    expect(screen.getByText("Ava invited you to a room")).toBeInTheDocument();
    expect(screen.getByRole("link", { name: /3 new replies/ })).toHaveAttribute("href", "/prompts/p1/takes/t1");
  });

  it("accepts a friend request through the server and re-reads", async () => {
    const user = userEvent.setup();
    inbox = [row({})];
    unread = 1;
    render(<NotificationBell />);
    await user.click(await screen.findByRole("button", { name: /Notifications/ }));
    await user.click(screen.getByRole("button", { name: "Accept" }));

    await waitFor(() => expect(rpc).toHaveBeenCalledWith("accept_friend_request", { p_user_id: "u1" }));
    await waitFor(() => expect(rpc).toHaveBeenCalledWith("mark_notification_read", { p_item_key: "n:1" }));
  });

  it("joins a room invite and goes into the room", async () => {
    const user = userEvent.setup();
    inbox = [row({ item_key: "i:3", kind: "room_invite", ref_id: "inv1" })];
    unread = 1;
    rpc.mockImplementation(async (name: string) => {
      if (name === "list_inbox") return { data: inbox, error: null };
      if (name === "inbox_unread_count") return { data: unread, error: null };
      if (name === "accept_room_invite") return { data: { code: "ROOMCODE" }, error: null };
      return { data: true, error: null };
    });
    render(<NotificationBell />);
    await user.click(await screen.findByRole("button", { name: /Notifications/ }));
    await user.click(screen.getByRole("button", { name: "Join" }));

    await waitFor(() => expect(push).toHaveBeenCalledWith("/lobby/ROOMCODE"));
  });

  it("shows an expired invite without actions", async () => {
    const user = userEvent.setup();
    inbox = [row({ item_key: "i:3", kind: "room_invite", state: "expired", is_unread: false })];
    render(<NotificationBell />);
    await user.click(await screen.findByRole("button", { name: "Notifications" }));

    expect(screen.getByText("Ava's room invite expired")).toBeInTheDocument();
    expect(screen.queryByRole("button", { name: "Join" })).not.toBeInTheDocument();
  });

  it("shows the server's message when an action fails", async () => {
    const user = userEvent.setup();
    inbox = [row({ item_key: "i:3", kind: "room_invite", ref_id: "inv1" })];
    unread = 1;
    rpc.mockImplementation(async (name: string) => {
      if (name === "list_inbox") return { data: inbox, error: null };
      if (name === "inbox_unread_count") return { data: unread, error: null };
      if (name === "accept_room_invite") return { data: null, error: { message: "invite_not_found" } };
      return { data: true, error: null };
    });
    render(<NotificationBell />);
    await user.click(await screen.findByRole("button", { name: /Notifications/ }));
    await user.click(screen.getByRole("button", { name: "Join" }));

    expect(await screen.findByRole("alert")).toHaveTextContent("That invite is no longer available.");
  });

  it("can be mounted twice on one page (desktop header and mobile top bar) without a channel clash", async () => {
    const failures: unknown[] = [];
    const onRejection = (event: PromiseRejectionEvent) => failures.push(event.reason);
    window.addEventListener("unhandledrejection", onRejection);
    inbox = [row({})];
    unread = 1;
    render(
      <>
        <NotificationBell />
        <NotificationBell />
      </>,
    );
    expect(await screen.findAllByRole("button", { name: "Notifications, 1 new" })).toHaveLength(2);
    await waitFor(() => expect(openChannels.size).toBe(2));
    window.removeEventListener("unhandledrejection", onRejection);
    expect(failures).toEqual([]);
  });

  it("says so when there is nothing to show", async () => {
    const user = userEvent.setup();
    render(<NotificationBell />);
    await user.click(await screen.findByRole("button", { name: "Notifications" }));
    expect(screen.getByText("You're all caught up")).toBeInTheDocument();
  });
});
