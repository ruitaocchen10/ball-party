import { render, screen, waitFor } from "@testing-library/react";
import userEvent from "@testing-library/user-event";
import { describe, expect, it, vi } from "vitest";

vi.mock("@/app/settings/actions", () => ({ setProfilePrivate: vi.fn() }));

import { setProfilePrivate } from "@/app/settings/actions";
import { PrivateProfileToggle } from "./PrivateProfileToggle";

describe("PrivateProfileToggle", () => {
  it("explains the setting and saves immediately when toggled", async () => {
    vi.mocked(setProfilePrivate).mockResolvedValue({ error: null });
    const user = userEvent.setup();
    render(<PrivateProfileToggle initialPrivate={false} />);

    expect(screen.getByText(/only your friends can open your profile/i)).toBeInTheDocument();
    const checkbox = screen.getByRole("checkbox", { name: /private profile/i });
    expect(checkbox).not.toBeChecked();

    await user.click(checkbox);

    await waitFor(() => expect(setProfilePrivate).toHaveBeenCalledWith(true));
    expect(checkbox).toBeChecked();
  });

  it("reverts the checkbox and shows an error when saving fails", async () => {
    vi.mocked(setProfilePrivate).mockResolvedValue({ error: "We couldn’t save that. Please try again." });
    const user = userEvent.setup();
    render(<PrivateProfileToggle initialPrivate />);

    const checkbox = screen.getByRole("checkbox", { name: /private profile/i });
    await user.click(checkbox);

    await waitFor(() => expect(screen.getByRole("alert")).toHaveTextContent("We couldn’t save that. Please try again."));
    expect(checkbox).toBeChecked();
  });
});
