import { render, screen } from "@testing-library/react";
import userEvent from "@testing-library/user-event";
import { beforeEach, describe, expect, it, vi } from "vitest";

const rpc = vi.fn();
vi.mock("@/lib/supabase/client", () => ({ createClient: () => ({ rpc }) }));

import { FriendInviteCard } from "./FriendInviteCard";
import { InviteLinkCard } from "./InviteLinkCard";

const owner = { username: "ava", displayName: "Ava", avatarUrl: null, relationship: "none" as const };

beforeEach(() => rpc.mockReset());

describe("FriendInviteCard", () => {
  it("only sends the request when the visitor taps", async () => {
    const user = userEvent.setup();
    rpc.mockResolvedValue({ data: "requested", error: null });
    render(<FriendInviteCard code="ABC" owner={owner} />);

    expect(screen.getByText("Ava invited you")).toBeInTheDocument();
    expect(rpc).not.toHaveBeenCalled();

    await user.click(screen.getByRole("button", { name: "Add friend" }));
    expect(rpc).toHaveBeenCalledWith("redeem_friend_code", { p_code: "ABC" });
    expect(await screen.findByText("Friend request sent.")).toBeInTheDocument();
  });

  it("does not offer a second request to an existing friend", () => {
    render(<FriendInviteCard code="ABC" owner={{ ...owner, relationship: "friends" }} />);
    expect(screen.queryByRole("button", { name: "Add friend" })).not.toBeInTheDocument();
    expect(screen.getByText("You're already friends.")).toBeInTheDocument();
  });
});

describe("InviteLinkCard", () => {
  it("builds the link from the code and swaps it on reset", async () => {
    const user = userEvent.setup();
    rpc.mockResolvedValue({ data: "NEWCODE", error: null });
    render(<InviteLinkCard code="OLDCODE" />);

    expect(screen.getByLabelText("Invite link")).toHaveValue(`${window.location.origin}/friends/invite/OLDCODE`);

    await user.click(screen.getByRole("button", { name: "Reset invite link" }));
    await user.click(screen.getByRole("button", { name: "Confirm: Reset invite link" }));
    expect(rpc).toHaveBeenCalledWith("reset_friend_code");
    expect(await screen.findByDisplayValue(`${window.location.origin}/friends/invite/NEWCODE`)).toBeInTheDocument();
  });
});
