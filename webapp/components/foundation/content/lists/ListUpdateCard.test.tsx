import { render, screen } from "@testing-library/react";
import { describe, expect, it } from "vitest";

import type { ListUpdate } from "@/lib/foundation/lists/types";
import { ListUpdateCard } from "./ListUpdateCard";

const update: ListUpdate = {
  postId: "post-1",
  authorId: "friend",
  username: "sam",
  displayName: "Sam",
  avatarUrl: null,
  kind: "power_rankings",
  label: "Power Rankings",
  itemKind: "team",
  versionNo: 7,
  note: "Chiefs are back",
  savedAt: "2026-10-15T12:00:00Z",
  items: ["KC", "BUF", "DET", "PHI", "BAL"],
  previousItems: ["BUF", "DET", "PHI", "BAL", "KC"],
};

describe("ListUpdateCard", () => {
  it("is a take card: author, what was updated, the note, the whole list with its movement and a way into the replies", () => {
    render(<ListUpdateCard update={update} players={{}} viewerId="me" />);
    expect(screen.getByText("Sam")).toBeInTheDocument();
    expect(screen.getByText(/Updated their power rankings · V7/)).toBeInTheDocument();
    expect(screen.getByText("Chiefs are back")).toBeInTheDocument();
    expect(screen.getByText("Friends only")).toBeInTheDocument();
    expect(screen.getAllByRole("listitem")).toHaveLength(5);
    expect(screen.getByText("Up 4")).toBeInTheDocument();
    expect(screen.getAllByText(/^Down 1$/)).toHaveLength(4);
    expect(screen.getByRole("link", { name: /Comment on Sam's take/ })).toHaveAttribute("href", "/lists/updates/post-1");
  });

  it("shows the whole list and the history link on its own page", () => {
    render(<ListUpdateCard update={update} players={{}} viewerId="me" full />);
    expect(screen.getAllByRole("listitem")).toHaveLength(5);
    expect(screen.getByRole("link", { name: "See the whole history" })).toHaveAttribute("href", "/u/sam/lists/power_rankings");
    expect(screen.queryByRole("link", { name: /Comment on/ })).not.toBeInTheDocument();
  });
});
