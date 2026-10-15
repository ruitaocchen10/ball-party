import { render, screen } from "@testing-library/react";
import userEvent from "@testing-library/user-event";
import { beforeEach, describe, expect, it, vi } from "vitest";

const rpc = vi.fn();
vi.mock("@/lib/supabase/client", () => ({ createClient: () => ({ rpc }) }));

import { InviteFriendsModal } from "./InviteFriendsModal";

const friends = [
  { profile_id: "f1", username: "ava", display_name: "Ava", avatar_url: null, since: "2026-01-01" },
  { profile_id: "f2", username: "ben", display_name: "Ben", avatar_url: null, since: "2026-01-02" },
];

beforeEach(() => rpc.mockReset());

describe("InviteFriendsModal", () => {
  it("lists friends and shows the server's answer per friend", async () => {
    const user = userEvent.setup();
    rpc.mockImplementation(async (name: string, args?: { p_friend_id?: string }) => {
      if (name === "list_friends") return { data: friends, error: null };
      return { data: args?.p_friend_id === "f1" ? "invited" : "room_full", error: null };
    });
    render(<InviteFriendsModal lobbyId="lobby-1" onClose={() => {}} />);

    await user.click(await screen.findByRole("button", { name: "Invite Ava" }));
    expect(rpc).toHaveBeenCalledWith("invite_friend_to_room", { p_lobby_id: "lobby-1", p_friend_id: "f1" });
    expect(await screen.findByText("Invited")).toBeInTheDocument();
    expect(screen.queryByRole("button", { name: "Invite Ava" })).not.toBeInTheDocument();

    await user.click(screen.getByRole("button", { name: "Invite Ben" }));
    expect(await screen.findByText("Room full")).toBeInTheDocument();
  });

  it("lets the viewer retry after an error", async () => {
    const user = userEvent.setup();
    rpc.mockImplementation(async (name: string) =>
      name === "list_friends"
        ? { data: friends.slice(0, 1), error: null }
        : { data: null, error: { message: "rate_limited" } },
    );
    render(<InviteFriendsModal lobbyId="lobby-1" onClose={() => {}} />);

    await user.click(await screen.findByRole("button", { name: "Invite Ava" }));
    expect(await screen.findByRole("alert")).toHaveTextContent("Too many invites");
    expect(screen.getByRole("button", { name: "Invite Ava" })).toHaveTextContent("Try again");
  });

  it("points at the profile Friends tab when there are no friends", async () => {
    rpc.mockResolvedValue({ data: [], error: null });
    render(<InviteFriendsModal lobbyId="lobby-1" onClose={() => {}} />);
    expect(await screen.findByRole("link", { name: "Find friends" })).toHaveAttribute("href", "/friends");
  });
});
