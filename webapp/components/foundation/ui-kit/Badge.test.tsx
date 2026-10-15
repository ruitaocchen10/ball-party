import { render, screen } from "@testing-library/react";
import { describe, expect, it } from "vitest";

import { Badge } from "./Badge";
import { EmptyState } from "./EmptyState";

describe("Badge", () => {
  it("is a light chip by default", () => {
    render(<Badge>You</Badge>);

    expect(screen.getByText("You")).toHaveClass("bg-fg", "text-surface");
  });

  it.each([
    ["success", "bg-grade-elite"],
    ["hidden", "bg-hidden"],
    ["muted", "bg-surface"],
    ["scrim", "bg-surface/80"],
  ] as const)("renders the %s tone", (tone, cls) => {
    render(<Badge tone={tone}>Tag</Badge>);

    expect(screen.getByText("Tag")).toHaveClass(cls);
  });

  it("renders an icon before the label, and the xs size", () => {
    render(
      <Badge size="xs" icon={<svg data-testid="icon" />}>
        Locked
      </Badge>,
    );

    const badge = screen.getByText("Locked");
    expect(badge).toHaveClass("type-label-xs");
    expect(badge.firstElementChild).toBe(screen.getByTestId("icon"));
  });
});

describe("EmptyState", () => {
  it("shows a title and message", () => {
    render(<EmptyState title="Quiet in here">Nothing yet.</EmptyState>);

    expect(screen.getByText("Quiet in here")).toBeInTheDocument();
    expect(screen.getByText("Nothing yet.")).toBeInTheDocument();
  });

  it("works with just a message", () => {
    render(<EmptyState>No takes yet.</EmptyState>);

    expect(screen.getByText("No takes yet.")).toBeInTheDocument();
  });
});
