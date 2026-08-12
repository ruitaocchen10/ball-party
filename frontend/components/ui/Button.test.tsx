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
  ] as const)("keeps the %s button hit target rectangular at every width", (variant, fullWidth) => {
    render(
      <Button variant={variant} fullWidth={fullWidth}>
        Place bid
      </Button>,
    );

    const button = screen.getByRole("button", { name: "Place bid" });
    const label = screen.getByText("Place bid");

    expect(button).not.toHaveClass("-skew-x-7");
    expect(button).toHaveClass(fullWidth ? "w-full" : "shrink-0");
    expect(label.tagName).toBe("SPAN");
    expect(label).toHaveClass("-skew-x-7");
  });

  it("keeps the navigation button's hit target rectangular", () => {
    render(<ButtonLink href="/room">Join room</ButtonLink>);

    const link = screen.getByRole("link", { name: "Join room" });
    const label = screen.getByText("Join room");

    expect(link).not.toHaveClass("-skew-x-7");
    expect(label.tagName).toBe("SPAN");
    expect(label).toHaveClass("-skew-x-7");
  });
});
