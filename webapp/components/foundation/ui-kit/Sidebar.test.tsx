import { render, screen, within } from "@testing-library/react";
import { describe, expect, it, vi } from "vitest";

vi.mock("next/navigation", () => ({ usePathname: () => "/" }));
vi.mock("@/lib/platform/lobbies/actions", () => ({ playSolo: vi.fn() }));
vi.mock("@/components/foundation/notifications/NotificationBell", () => ({ NotificationBell: () => null }));

import { Sidebar } from "./Sidebar";

function soloNav() {
  return within(screen.getByRole("navigation", { name: "Solo games" }));
}

describe("Sidebar — Solo games", () => {
  it("starts Higher or Lower in one tap but sends a game with a start-time choice to the Solo page", () => {
    render(<Sidebar displayName="Ava" />);

    // One tap: a form button that deals a fresh run.
    expect(soloNav().getByRole("button", { name: "Higher or Lower" })).toBeInTheDocument();
    // QB Season Builder's mode is chosen at start, so one tap must not skip it.
    expect(soloNav().getByRole("link", { name: "QB Season Builder" })).toHaveAttribute("href", "/solo");
    expect(soloNav().queryByRole("button", { name: "QB Season Builder" })).not.toBeInTheDocument();

    const games = Array.from(screen.getByRole("navigation", { name: "Solo games" }).querySelectorAll("a, button")).map((item) => item.textContent);
    expect(games).toEqual(["QB Season Builder", "Higher or Lower"]);
  });

  it("offers a visitor with no session the same entries, with no detour through sign-up", () => {
    render(<Sidebar />);

    expect(soloNav().getByRole("button", { name: "Higher or Lower" })).toBeInTheDocument();
    expect(soloNav().getByRole("link", { name: "QB Season Builder" })).toHaveAttribute("href", "/solo");
    for (const link of soloNav().queryAllByRole("link")) {
      expect(link.getAttribute("href")).not.toMatch(/signup/);
    }
  });
});
