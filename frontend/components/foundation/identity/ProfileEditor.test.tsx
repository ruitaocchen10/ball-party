import { render, screen, waitFor } from "@testing-library/react";
import userEvent from "@testing-library/user-event";
import { describe, expect, it, vi } from "vitest";

vi.mock("@/app/profile/actions", () => ({ updateProfile: vi.fn() }));

import { ProfileEditor } from "./ProfileEditor";

describe("ProfileEditor", () => {
  it("opens a dialog and returns focus to its trigger after Escape", async () => {
    const user = userEvent.setup();
    render(<ProfileEditor displayName="Taylor" avatarUrl={null} userId="player-1" />);

    const trigger = screen.getByRole("button", { name: "Edit profile" });
    await user.click(trigger);

    expect(screen.getByRole("dialog", { name: "Edit profile" })).toBeInTheDocument();
    expect(screen.getByLabelText("Display name")).toHaveFocus();
    expect(screen.getByRole("button", { name: "Change profile photo" })).toBeInTheDocument();
    expect(screen.queryByRole("button", { name: "Choose Captain avatar" })).not.toBeInTheDocument();

    await user.click(screen.getByRole("button", { name: "Change profile photo" }));

    expect(screen.getByRole("dialog", { name: "Choose your look" })).toBeInTheDocument();
    expect(screen.getByRole("button", { name: "Choose Captain avatar" })).toBeInTheDocument();
    expect(screen.getByText("Upload from device")).toBeInTheDocument();

    await user.keyboard("{Escape}");

    await waitFor(() => expect(screen.queryByRole("dialog")).not.toBeInTheDocument());
    expect(trigger).toHaveFocus();
  });
});
