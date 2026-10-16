import { render, screen } from "@testing-library/react";
import { expect, it } from "vitest";

import { CalendarKey, GameRow, GamesSummary, OpenEcho, PostCard } from "./CalendarCards";
import { ScheduleSlotSummary } from "./ScheduleSlotCard";
import type { CalendarPost, ScheduleSlot } from "@/lib/foundation/content/prompts/schedule";

const post = (status: CalendarPost["status"]): CalendarPost => ({
  id: "p",
  template_kind: "game_pick",
  template_name: "Game Picks",
  prompt_text: "Chiefs vs. Bills: Who wins?",
  status,
  created_at: "2026-10-15T14:00:00Z",
  lock_at: "2026-10-18T17:00:00Z",
});

const slot = (state: ScheduleSlot["state"]): ScheduleSlot => ({
  id: "s",
  season: 2026,
  week: 6,
  kind: "weekly_awards",
  game_id: null,
  state,
  display_state: state === "published" ? "live" : state,
  opens_at: state === "ready" ? "2026-10-16T18:00:00Z" : null,
  lock_at: "2026-10-18T17:00:00Z",
  post_id: null,
  publish_error: null,
  has_draft: state !== "empty",
  caption: null,
  missing: [],
  due_at: "2026-10-18T17:00:00Z",
  needs_attention: false,
  attention: null,
});

it("draws a game as plain text with a primetime tag, and a month day's games as a count", () => {
  const game = { id: "g", kickoff: "2026-10-18T00:20:00Z", away: "BUF", home: "KC", primetime: true };
  const { container, rerender } = render(<GameRow game={game} />);
  expect(screen.getByText("BUF @ KC")).toBeInTheDocument();
  expect(screen.getByText("Prime")).toBeInTheDocument();
  expect(container.querySelector(".border")).toBeNull();

  rerender(<GamesSummary games={[game, { ...game, id: "h", primetime: false }]} />);
  expect(screen.getByText("2 games")).toBeInTheDocument();
  expect(screen.getByText("1 prime")).toBeInTheDocument();
});

it("tells planned, ready and published prompts apart by their outline", () => {
  const { container, rerender } = render(<ScheduleSlotSummary slot={slot("empty")} compact />);
  expect(container.firstElementChild).toHaveClass("border-dashed", "opacity-70");

  rerender(<ScheduleSlotSummary slot={slot("draft")} compact />);
  expect(container.firstElementChild).toHaveClass("border-dashed");
  expect(container.firstElementChild).not.toHaveClass("opacity-70");

  rerender(<ScheduleSlotSummary slot={slot("ready")} compact />);
  expect(container.firstElementChild).toHaveClass("border-l-fg");
  expect(container.firstElementChild).not.toHaveClass("border-dashed");

  rerender(<PostCard post={post("open")} />);
  expect(container.firstElementChild).toHaveClass("bg-panel", "border-l-grade-elite");
  expect(screen.getByText("Open")).toBeInTheDocument();

  rerender(<PostCard post={post("resolved")} />);
  expect(container.firstElementChild).toHaveClass("opacity-60");
});

it("shows the opened reminder on the day a prompt opened and a key for every look", () => {
  const { rerender } = render(<OpenEcho post={post("open")} />);
  expect(screen.getByText(/^Opened /)).toBeInTheDocument();
  expect(screen.getByText("Chiefs vs. Bills: Who wins?")).toBeInTheDocument();

  rerender(<CalendarKey />);
  for (const name of ["NFL game", "Empty slot", "Draft", "Ready", "Open", "Locked", "Resolved or void", "Opened earlier"]) {
    expect(screen.getByText(name)).toBeInTheDocument();
  }
});
