import { render, screen } from "@testing-library/react";
import { describe, expect, it } from "vitest";

import { ScopeToggle } from "./LeaderboardParts";
import { boardHref } from "@/lib/foundation/content/leaderboard/boards";

describe("ScopeToggle", () => {
  it("marks the active scope and keeps the board and window when switching", () => {
    render(<ScopeToggle scope="friends" hrefFor={(scope) => boardHref({ board: "gamer", window: "month", scope })} />);

    const nav = screen.getByRole("navigation", { name: "Leaderboard scope" });
    expect(nav.querySelector('[aria-current="page"]')).toHaveTextContent("Friends");
    expect(screen.getByRole("link", { name: "Everyone" })).toHaveAttribute("href", "/leaderboard?board=gamer&window=month");
  });
});
