import { render, screen } from "@testing-library/react";
import userEvent from "@testing-library/user-event";
import { beforeEach, describe, expect, it, vi } from "vitest";

const rpc = vi.fn();
vi.mock("@/lib/supabase/client", () => ({ createClient: () => ({ rpc }) }));

import { PlayerSearch } from "./PlayerSearch";

const hit = { profile_id: "p1", username: "ava", display_name: "Ava", avatar_url: null, relationship: "none" };

beforeEach(() => rpc.mockReset());

async function search(user: ReturnType<typeof userEvent.setup>, text: string) {
  await user.type(screen.getByLabelText("Find by username"), text);
  await user.click(screen.getByRole("button", { name: "Search" }));
}

describe("PlayerSearch", () => {
  it("finds an exact username (ignoring a leading @) and sends a request", async () => {
    const user = userEvent.setup();
    rpc.mockImplementation(async (name: string) =>
      name === "search_users_by_username" ? { data: [hit], error: null } : { data: "requested", error: null },
    );
    const onChanged = vi.fn();
    render(<PlayerSearch onChanged={onChanged} />);

    await search(user, "@ava");
    expect(rpc).toHaveBeenCalledWith("search_users_by_username", { p_query: "ava" });

    await user.click(await screen.findByRole("button", { name: "Add friend" }));
    expect(rpc).toHaveBeenCalledWith("send_friend_request", { p_username: "ava" });
    expect(await screen.findByText("Friend request sent.")).toBeInTheDocument();
    expect(screen.getByText("Requested")).toBeInTheDocument();
    expect(onChanged).toHaveBeenCalled();
  });

  it("says nothing specific when no one matches", async () => {
    const user = userEvent.setup();
    rpc.mockResolvedValue({ data: [], error: null });
    render(<PlayerSearch onChanged={vi.fn()} />);

    await search(user, "nobody");
    expect(await screen.findByText("No player found with that exact username.")).toBeInTheDocument();
  });

  it("shows 'unavailable' neutrally", async () => {
    const user = userEvent.setup();
    rpc.mockImplementation(async (name: string) =>
      name === "search_users_by_username" ? { data: [hit], error: null } : { data: "unavailable", error: null },
    );
    render(<PlayerSearch onChanged={vi.fn()} />);

    await search(user, "ava");
    await user.click(await screen.findByRole("button", { name: "Add friend" }));
    expect(await screen.findByText("Couldn't add that player.")).toBeInTheDocument();
    expect(screen.queryByText(/block/i)).not.toBeInTheDocument();
  });

  it("offers no add button for someone who is already a friend", async () => {
    const user = userEvent.setup();
    rpc.mockResolvedValue({ data: [{ ...hit, relationship: "friends" }], error: null });
    render(<PlayerSearch onChanged={vi.fn()} />);

    await search(user, "ava");
    expect(await screen.findByText("Friends")).toBeInTheDocument();
    expect(screen.queryByRole("button", { name: "Add friend" })).not.toBeInTheDocument();
  });
});
