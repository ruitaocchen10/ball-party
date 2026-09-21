import { render, screen, within } from "@testing-library/react";
import { describe, expect, it, vi } from "vitest";

vi.mock("next/navigation", () => ({ usePathname: () => "/" }));
vi.mock("@/lib/platform/lobbies/actions", () => ({ playSolo: vi.fn() }));

import { Sidebar } from "./Sidebar";

function soloNav() {
  return within(screen.getByRole("navigation", { name: "Solo games" }));
}

describe("Sidebar — Solo games", () => {
  it("starts Higher or Lower in one tap but sends a game with a start-time choice to the Solo page", () => {
    render(<Sidebar displayName="Ava" canPlaySolo />);

    // One tap: a form button that deals a fresh run.
    expect(soloNav().getByRole("button", { name: "Higher or lower" })).toBeInTheDocument();
    // QB Season Builder's mode is chosen at start, so one tap must not skip it.
    expect(soloNav().getByRole("link", { name: "QB season builder" })).toHaveAttribute("href", "/solo");
    expect(soloNav().queryByRole("button", { name: "QB season builder" })).not.toBeInTheDocument();
  });

  it("sends a visitor with no session to sign up for either game", () => {
    render(<Sidebar canPlaySolo={false} />);

    for (const name of ["Higher or lower", "QB season builder"]) {
      expect(soloNav().getByRole("link", { name })).toHaveAttribute("href", "/signup?next=%2Fsolo");
    }
  });
});
