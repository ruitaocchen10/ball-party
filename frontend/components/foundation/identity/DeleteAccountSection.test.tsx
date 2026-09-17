import { render, screen, waitFor } from "@testing-library/react";
import userEvent from "@testing-library/user-event";
import { describe, expect, it, vi } from "vitest";

const push = vi.fn();
vi.mock("next/navigation", () => ({ useRouter: () => ({ push }) }));
vi.mock("@/app/settings/actions", () => ({ deleteAccount: vi.fn() }));

import { deleteAccount } from "@/app/settings/actions";
import { DeleteAccountSection } from "./DeleteAccountSection";

describe("DeleteAccountSection", () => {
  it("requires a second confirming click before deleting, then navigates home", async () => {
    vi.mocked(deleteAccount).mockResolvedValue(undefined);
    const user = userEvent.setup();
    render(<DeleteAccountSection />);

    await user.click(screen.getByRole("button", { name: "Delete account" }));
    expect(deleteAccount).not.toHaveBeenCalled();

    await user.click(screen.getByRole("button", { name: "Yes, permanently delete my account" }));

    await waitFor(() => expect(deleteAccount).toHaveBeenCalled());
    await waitFor(() => expect(push).toHaveBeenCalledWith("/"));
  });

  it("cancel returns to the single button without deleting", async () => {
    const user = userEvent.setup();
    render(<DeleteAccountSection />);

    await user.click(screen.getByRole("button", { name: "Delete account" }));
    await user.click(screen.getByRole("button", { name: "Cancel" }));

    expect(screen.getByRole("button", { name: "Delete account" })).toBeInTheDocument();
    expect(deleteAccount).not.toHaveBeenCalled();
  });

  it("shows an error and does not navigate when deletion fails", async () => {
    vi.mocked(deleteAccount).mockRejectedValue(new Error("boom"));
    const user = userEvent.setup();
    render(<DeleteAccountSection />);

    await user.click(screen.getByRole("button", { name: "Delete account" }));
    await user.click(screen.getByRole("button", { name: "Yes, permanently delete my account" }));

    await waitFor(() =>
      expect(screen.getByRole("alert")).toHaveTextContent("We couldn’t delete your account. Please try again."),
    );
    expect(push).not.toHaveBeenCalled();
  });
});
