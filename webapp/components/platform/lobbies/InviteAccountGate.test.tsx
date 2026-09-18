import { render, screen } from "@testing-library/react";
import { describe, expect, it } from "vitest";

import { InviteAccountGate } from "./InviteAccountGate";

describe("InviteAccountGate", () => {
  it("sends a signed-out invitee to account creation for this room, not a guest form", () => {
    render(<InviteAccountGate code="ABCDE" />);

    expect(screen.getByRole("link", { name: "Create an account to join" })).toHaveAttribute(
      "href",
      "/signup?next=%2Flobby%2FABCDE",
    );
    expect(screen.queryByRole("textbox")).not.toBeInTheDocument();
    expect(screen.queryByRole("button", { name: "Join game" })).not.toBeInTheDocument();
  });

  it("still offers sign-in for a returning account holder", () => {
    render(<InviteAccountGate code="ABCDE" />);

    expect(screen.getByRole("link", { name: "Sign in instead" })).toHaveAttribute(
      "href",
      "/login?next=%2Flobby%2FABCDE",
    );
  });
});
