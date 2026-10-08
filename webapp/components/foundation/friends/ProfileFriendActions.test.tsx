import { render, screen } from "@testing-library/react";
import userEvent from "@testing-library/user-event";
import { beforeEach, describe, expect, it, vi } from "vitest";

const rpc = vi.fn();
const refresh = vi.fn();
vi.mock("@/lib/supabase/client", () => ({ createClient: () => ({ rpc }) }));
vi.mock("next/navigation", () => ({ useRouter: () => ({ refresh }) }));

import type { Relationship } from "@/lib/foundation/friends/friends";
import { ProfileFriendActions } from "./ProfileFriendActions";

function renderFor(relationship: Relationship) {
  return render(<ProfileFriendActions profileId="p1" username="ava" displayName="Ava" relationship={relationship} />);
}

beforeEach(() => {
  rpc.mockReset();
  refresh.mockReset();
  rpc.mockResolvedValue({ data: true, error: null });
});

describe("ProfileFriendActions", () => {
  it("offers Add friend to a stranger and refreshes after", async () => {
    const user = userEvent.setup();
    rpc.mockResolvedValue({ data: "requested", error: null });
    renderFor("none");

    await user.click(screen.getByRole("button", { name: "Add friend" }));
    expect(rpc).toHaveBeenCalledWith("send_friend_request", { p_username: "ava" });
    expect(await screen.findByText("Friend request sent.")).toBeInTheDocument();
    expect(refresh).toHaveBeenCalled();
  });

  it("offers accept and decline for an incoming request", async () => {
    const user = userEvent.setup();
    renderFor("incoming");

    await user.click(screen.getByRole("button", { name: "Accept request" }));
    expect(rpc).toHaveBeenCalledWith("accept_friend_request", { p_user_id: "p1" });
    await user.click(screen.getByRole("button", { name: "Decline" }));
    expect(rpc).toHaveBeenCalledWith("decline_friend_request", { p_user_id: "p1" });
  });

  it("lets you cancel your own request", async () => {
    const user = userEvent.setup();
    renderFor("outgoing");
    await user.click(screen.getByRole("button", { name: "Cancel request" }));
    expect(rpc).toHaveBeenCalledWith("cancel_friend_request", { p_user_id: "p1" });
  });

  it("confirms before removing a friend", async () => {
    const user = userEvent.setup();
    renderFor("friends");

    await user.click(screen.getByRole("button", { name: "Remove Ava as a friend" }));
    expect(rpc).not.toHaveBeenCalled();
    await user.click(screen.getByRole("button", { name: "Confirm: Remove Ava as a friend" }));
    expect(rpc).toHaveBeenCalledWith("remove_friend", { p_user_id: "p1" });
  });

  it("offers Unblock when you blocked them", async () => {
    const user = userEvent.setup();
    renderFor("blocked");
    await user.click(screen.getByRole("button", { name: "Unblock" }));
    expect(rpc).toHaveBeenCalledWith("unblock_user", { p_user_id: "p1" });
  });

  it("renders nothing for yourself", () => {
    const { container } = renderFor("self");
    expect(container).toBeEmptyDOMElement();
  });

  it("shows an error and does not refresh when the server refuses", async () => {
    const user = userEvent.setup();
    rpc.mockResolvedValue({ data: null, error: { message: "rate_limited" } });
    renderFor("none");

    await user.click(screen.getByRole("button", { name: "Add friend" }));
    expect(await screen.findByText("Too many tries. Wait a bit and try again.")).toBeInTheDocument();
    expect(refresh).not.toHaveBeenCalled();
  });
});
