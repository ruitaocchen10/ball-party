import { render, screen, waitFor } from "@testing-library/react";
import userEvent from "@testing-library/user-event";
import { describe, expect, it, vi } from "vitest";

vi.mock("@/app/settings/actions", () => ({ updateRankingsVisibility: vi.fn() }));

import { updateRankingsVisibility } from "@/app/settings/actions";
import { RankingsVisibilityToggle } from "./RankingsVisibilityToggle";

describe("RankingsVisibilityToggle", () => {
  it("saves immediately when toggled", async () => {
    vi.mocked(updateRankingsVisibility).mockResolvedValue({ error: null });
    const user = userEvent.setup();
    render(<RankingsVisibilityToggle initialVisible />);

    const checkbox = screen.getByRole("checkbox", { name: /show me in knower rankings/i });
    expect(checkbox).toBeChecked();

    await user.click(checkbox);

    await waitFor(() => expect(updateRankingsVisibility).toHaveBeenCalledWith(false));
    expect(checkbox).not.toBeChecked();
  });

  it("reverts the checkbox and shows an error when saving fails", async () => {
    vi.mocked(updateRankingsVisibility).mockResolvedValue({ error: "We couldn’t save that. Please try again." });
    const user = userEvent.setup();
    render(<RankingsVisibilityToggle initialVisible />);

    const checkbox = screen.getByRole("checkbox", { name: /show me in knower rankings/i });
    await user.click(checkbox);

    await waitFor(() => expect(screen.getByRole("alert")).toHaveTextContent("We couldn’t save that. Please try again."));
    expect(checkbox).toBeChecked();
  });
});
