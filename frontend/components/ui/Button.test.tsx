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
});
