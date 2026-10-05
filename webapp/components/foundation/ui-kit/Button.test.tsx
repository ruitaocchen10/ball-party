import { render, screen } from "@testing-library/react";
import { describe, expect, it } from "vitest";

import { Button, ButtonLink } from "./Button";

describe("Button", () => {
  it.each([
    ["solid", true],
    ["solid", false],
    ["ghost", true],
    ["ghost", false],
    ["ink", true],
    ["ink", false],
  ] as const)("sizes the %s button correctly for fullWidth %s", (variant, fullWidth) => {
    render(
      <Button variant={variant} fullWidth={fullWidth}>
        Place bid
      </Button>,
    );

    const button = screen.getByRole("button", { name: "Place bid" });

    expect(button).toHaveClass(fullWidth ? "w-full" : "shrink-0");
  });

  it("renders the navigation button's label directly", () => {
    render(<ButtonLink href="/room">Join room</ButtonLink>);

    const link = screen.getByRole("link", { name: "Join room" });

    expect(link).toHaveTextContent("Join room");
  });

  it("has a compact size for card and dialog footers", () => {
    render(
      <Button size="sm" fullWidth={false}>
        Done
      </Button>,
    );

    const button = screen.getByRole("button", { name: "Done" });

    expect(button).toHaveClass("min-h-9", "type-label-lg");
    expect(button).not.toHaveClass("min-h-12");
  });

  it.each([
    ["text", "text-fg-muted"],
    ["danger", "text-hidden-text"],
  ] as const)("renders the %s variant", (variant, cls) => {
    render(<Button variant={variant}>Cancel</Button>);

    expect(screen.getByRole("button", { name: "Cancel" })).toHaveClass(cls);
  });

  it("gives a link the same size options", () => {
    render(
      <ButtonLink href="/room" size="sm">
        Join room
      </ButtonLink>,
    );

    expect(screen.getByRole("link", { name: "Join room" })).toHaveClass("min-h-9");
  });
});
