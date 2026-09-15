import { fireEvent, render, screen } from "@testing-library/react";
import { describe, expect, it, vi } from "vitest";

import { FeedbackModal } from "@/components/feedback/FeedbackModal";

describe("FeedbackModal", () => {
  it("switches the prompt to match a feature request", () => {
    render(<FeedbackModal route="/party" onClose={vi.fn()} />);

    fireEvent.click(screen.getByRole("button", { name: "Request a feature" }));

    expect(screen.getByText("What would you like to see?")).toBeInTheDocument();
    expect(screen.getByPlaceholderText("Describe the feature that would help.")).toBeInTheDocument();
  });

  it("closes from the close control", () => {
    const onClose = vi.fn();
    render(<FeedbackModal route="/party" onClose={onClose} />);

    fireEvent.click(screen.getAllByRole("button", { name: "Close feedback" })[1]!);

    expect(onClose).toHaveBeenCalledOnce();
  });
});
