import { render, screen } from "@testing-library/react";
import userEvent from "@testing-library/user-event";
import { beforeEach, describe, expect, it, vi } from "vitest";

const rpc = vi.fn();
vi.mock("@/lib/supabase/client", () => ({ createClient: () => ({ rpc }) }));

import { FriendsManager, type FriendsData } from "./FriendsManager";

const ava = { profileId: "p-ava", username: "ava", displayName: "Ava", avatarUrl: null };
const ben = { profileId: "p-ben", username: "ben", displayName: "Ben", avatarUrl: null };
const cy = { profileId: "p-cy", username: "cy", displayName: "Cy", avatarUrl: null };

const empty: FriendsData = { friends: [], incoming: [], outgoing: [], blocked: [] };

/** Answers the three list RPCs a reload makes, and any action RPC with success. */
function answerLists(lists: { friends?: unknown[]; requests?: unknown[]; blocked?: unknown[] } = {}) {
  rpc.mockImplementation(async (name: string) => {
    if (name === "list_friends") return { data: lists.friends ?? [], error: null };
    if (name === "list_friend_requests") return { data: lists.requests ?? [], error: null };
    if (name === "list_blocked_users") return { data: lists.blocked ?? [], error: null };
    return { data: true, error: null };
  });
}

beforeEach(() => rpc.mockReset());

describe("FriendsManager", () => {
  it("shows an empty state with no friends and hides requests and blocks", () => {
    render(<FriendsManager initial={empty} inviteCode="ABC123" />);
    expect(screen.getByText("No friends yet")).toBeInTheDocument();
    expect(screen.queryByText(/Requests/)).not.toBeInTheDocument();
    expect(screen.queryByText(/Blocked/)).not.toBeInTheDocument();
  });

  it("links friends to their profile", () => {
    render(<FriendsManager initial={{ ...empty, friends: [ava] }} inviteCode={null} />);
    expect(screen.getByRole("link", { name: /Ava/ })).toHaveAttribute("href", "/u/ava");
  });

  it("accepts an incoming request and reloads the lists", async () => {
    const user = userEvent.setup();
    answerLists({
      friends: [{ profile_id: "p-ben", username: "ben", display_name: "Ben", avatar_url: null, since: "x" }],
    });
    render(<FriendsManager initial={{ ...empty, incoming: [ben] }} inviteCode={null} />);

    await user.click(screen.getByRole("button", { name: "Accept request from Ben" }));
    expect(rpc).toHaveBeenCalledWith("accept_friend_request", { p_user_id: "p-ben" });
    expect(await screen.findByRole("link", { name: /Ben/ })).toBeInTheDocument();
    expect(screen.queryByRole("button", { name: /Accept request/ })).not.toBeInTheDocument();
  });

  it("cancels an outgoing request", async () => {
    const user = userEvent.setup();
    answerLists();
    render(<FriendsManager initial={{ ...empty, outgoing: [cy] }} inviteCode={null} />);

    expect(screen.getByText(/Request sent/)).toBeInTheDocument();
    await user.click(screen.getByRole("button", { name: "Cancel request to Cy" }));
    expect(rpc).toHaveBeenCalledWith("cancel_friend_request", { p_user_id: "p-cy" });
  });

  it("asks before removing a friend", async () => {
    const user = userEvent.setup();
    answerLists();
    render(<FriendsManager initial={{ ...empty, friends: [ava] }} inviteCode={null} />);

    await user.click(screen.getByRole("button", { name: "Remove Ava" }));
    expect(rpc).not.toHaveBeenCalledWith("remove_friend", expect.anything());
    await user.click(screen.getByRole("button", { name: "Confirm: Remove Ava" }));
    expect(rpc).toHaveBeenCalledWith("remove_friend", { p_user_id: "p-ava" });
  });

  it("unblocks from the blocked list without linking to the profile", async () => {
    const user = userEvent.setup();
    answerLists();
    render(<FriendsManager initial={{ ...empty, blocked: [cy] }} inviteCode={null} />);

    expect(screen.queryByRole("link", { name: /Cy/ })).not.toBeInTheDocument();
    await user.click(screen.getByRole("button", { name: "Unblock Cy" }));
    expect(rpc).toHaveBeenCalledWith("unblock_user", { p_user_id: "p-cy" });
  });

  it("shows a message when an action fails", async () => {
    const user = userEvent.setup();
    rpc.mockResolvedValue({ data: null, error: { message: "guests_cannot_have_friends" } });
    render(<FriendsManager initial={{ ...empty, incoming: [ben] }} inviteCode={null} />);

    await user.click(screen.getByRole("button", { name: "Accept request from Ben" }));
    expect(await screen.findByRole("alert")).toHaveTextContent("Friends need a real account.");
  });
});
