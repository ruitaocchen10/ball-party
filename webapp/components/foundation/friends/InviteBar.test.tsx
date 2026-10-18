import { render, screen } from "@testing-library/react";
import userEvent from "@testing-library/user-event";
import { afterEach, describe, expect, it, vi } from "vitest";

import { InviteBar } from "./InviteBar";

afterEach(() => {
  vi.restoreAllMocks();
  Object.defineProperty(navigator, "share", { value: undefined, configurable: true });
});

describe("InviteBar", () => {
  it("shares the invite link with the system share sheet when there is one", async () => {
    const user = userEvent.setup();
    const share = vi.fn().mockResolvedValue(undefined);
    Object.defineProperty(navigator, "share", { value: share, configurable: true });
    render(<InviteBar code="ABC123" />);

    await user.click(screen.getByRole("button", { name: "Invite" }));
    expect(share).toHaveBeenCalledWith(expect.objectContaining({ url: `${window.location.origin}/friends/invite/ABC123` }));
  });

  it("copies the link where there is no share sheet", async () => {
    const user = userEvent.setup();
    const writeText = vi.spyOn(navigator.clipboard, "writeText").mockResolvedValue(undefined);
    render(<InviteBar code="ABC123" />);

    await user.click(screen.getByRole("button", { name: "Invite" }));
    expect(writeText).toHaveBeenCalledWith(`${window.location.origin}/friends/invite/ABC123`);
    expect(await screen.findByRole("button", { name: "Copied" })).toBeInTheDocument();
  });

  it("says so when the link can't be copied", async () => {
    const user = userEvent.setup();
    vi.spyOn(navigator.clipboard, "writeText").mockRejectedValue(new Error("denied"));
    render(<InviteBar code="ABC123" />);

    await user.click(screen.getByRole("button", { name: "Invite" }));
    expect(await screen.findByText(/Couldn't copy/)).toBeInTheDocument();
  });

  it("has no way to dismiss it", () => {
    render(<InviteBar code="ABC123" />);
    expect(screen.getAllByRole("button")).toHaveLength(1);
  });
});
