import { render, screen, waitFor } from "@testing-library/react";
import userEvent from "@testing-library/user-event";
import { beforeEach, describe, expect, it, vi } from "vitest";

vi.mock("@/app/profile/actions", () => ({ claimUsername: vi.fn(), checkUsernameAvailable: vi.fn() }));

import { checkUsernameAvailable, claimUsername } from "@/app/profile/actions";
import { isUsernameConfirmed } from "@/lib/foundation/identity/username";
import { UsernamePrompt } from "./UsernamePrompt";

describe("UsernamePrompt", () => {
  beforeEach(() => {
    window.localStorage.clear();
    vi.mocked(checkUsernameAvailable).mockResolvedValue({ available: true, error: null });
  });

  it("stays hidden once the username has been confirmed in this browser", () => {
    window.localStorage.setItem("bp.username-confirmed.u1", "1");
    render(<UsernamePrompt userId="u1" currentUsername="Taylor" />);
    expect(screen.queryByRole("dialog")).not.toBeInTheDocument();
  });

  it("keeps the generated username without a server call, then never shows again", async () => {
    const user = userEvent.setup();
    const { unmount } = render(<UsernamePrompt userId="u1" currentUsername="Taylor" />);

    expect(await screen.findByRole("dialog", { name: "Is this you?" })).toBeInTheDocument();
    expect(screen.getByLabelText(/^Username/)).toHaveValue("Taylor");

    await user.click(screen.getByRole("button", { name: "Keep this username" }));

    expect(claimUsername).not.toHaveBeenCalled();
    expect(screen.queryByRole("dialog")).not.toBeInTheDocument();
    expect(isUsernameConfirmed("u1")).toBe(true);

    unmount();
    render(<UsernamePrompt userId="u1" currentUsername="Taylor" />);
    expect(screen.queryByRole("dialog")).not.toBeInTheDocument();
  });

  it("claims a changed username and dismisses on success", async () => {
    vi.mocked(claimUsername).mockResolvedValue({ error: null, username: "Tay_QB" });
    const user = userEvent.setup();
    render(<UsernamePrompt userId="u1" currentUsername="Taylor" />);

    const field = await screen.findByLabelText(/^Username/);
    await user.clear(field);
    await user.type(field, "Tay_QB");
    await user.click(screen.getByRole("button", { name: "Save username" }));

    await waitFor(() => expect(claimUsername).toHaveBeenCalledWith("Tay_QB"));
    await waitFor(() => expect(screen.queryByRole("dialog")).not.toBeInTheDocument());
    expect(isUsernameConfirmed("u1")).toBe(true);
  });

  it("starts from the username chosen at signup and shows server refusals", async () => {
    vi.mocked(claimUsername).mockResolvedValue({ error: "That username is taken.", username: null });
    const user = userEvent.setup();
    render(<UsernamePrompt userId="u1" currentUsername="Taylor" preferredUsername="Tay_QB" />);

    expect(await screen.findByLabelText(/^Username/)).toHaveValue("Tay_QB");
    await user.click(screen.getByRole("button", { name: "Save username" }));

    await waitFor(() => expect(screen.getByRole("alert")).toHaveTextContent("That username is taken."));
    expect(screen.getByRole("dialog")).toBeInTheDocument();
    expect(isUsernameConfirmed("u1")).toBe(false);
  });

  it("can be skipped", async () => {
    const user = userEvent.setup();
    render(<UsernamePrompt userId="u1" currentUsername="Taylor" />);

    await user.click(await screen.findByRole("button", { name: "Skip" }));

    expect(claimUsername).not.toHaveBeenCalled();
    expect(isUsernameConfirmed("u1")).toBe(true);
  });
});
