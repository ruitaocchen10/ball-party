import { render, screen } from "@testing-library/react";
import userEvent from "@testing-library/user-event";
import { beforeEach, describe, expect, it, vi } from "vitest";

const rpc = vi.fn();
vi.mock("@/lib/supabase/client", () => ({ createClient: () => ({ rpc }) }));

import { ACTIVITY_PAGE_SIZE, type ActivityEvent } from "@/lib/foundation/friends/friends";
import { ActivityFeed } from "./ActivityFeed";

const base: ActivityEvent = {
  type: "pick_made",
  occurredAt: "2026-10-08T10:00:00Z",
  actorId: "a1",
  username: "ava",
  displayName: "Ava",
  avatarUrl: null,
  postId: "post-1",
  postCaption: "Week 5 picks",
  points: null,
  matchId: null,
  game: null,
  placement: null,
  rawScore: null,
  runMode: null,
};

beforeEach(() => rpc.mockReset());

describe("ActivityFeed", () => {
  it("renders the three event types without exposing picks", () => {
    render(
      <ActivityFeed
        hasFriends
        initial={[
          base,
          { ...base, type: "pick_result", points: 12, occurredAt: "2026-10-08T09:00:00Z" },
          { ...base, type: "match_result", game: "higher_or_lower", placement: 1, rawScore: 8, postId: null, matchId: "m1", occurredAt: "2026-10-08T08:00:00Z" },
        ]}
      />,
    );
    expect(screen.getByText(/made a pick on/)).toBeInTheDocument();
    expect(screen.getAllByRole("link", { name: "Week 5 picks" })[0]).toHaveAttribute("href", "/prompts/post-1");
    expect(screen.getByText(/scored 12 points on/)).toBeInTheDocument();
    expect(screen.getByText(/finished 1st in Higher or Lower · score 8/)).toBeInTheDocument();
  });

  it("explains an empty feed with no friends, and with friends", () => {
    const { rerender } = render(<ActivityFeed initial={[]} hasFriends={false} />);
    expect(screen.getByText("No friends yet")).toBeInTheDocument();
    expect(screen.getByRole("link", { name: "Find friends" })).toHaveAttribute("href", "/profile?tab=friends");

    rerender(<ActivityFeed initial={[]} hasFriends />);
    expect(screen.getByText("Nothing yet")).toBeInTheDocument();
  });

  it("hides Load more when the first page was short", () => {
    render(<ActivityFeed initial={[base]} hasFriends />);
    expect(screen.queryByRole("button", { name: "Load more" })).not.toBeInTheDocument();
  });

  it("loads the next page before the oldest event and stops when it comes back short", async () => {
    const user = userEvent.setup();
    const full = Array.from({ length: ACTIVITY_PAGE_SIZE }, (_, i) => ({
      ...base,
      postId: `p${i}`,
      occurredAt: new Date(Date.UTC(2026, 9, 8, 10, 0, 0) - i * 60_000).toISOString(),
    }));
    const oldest = full[full.length - 1].occurredAt;
    rpc.mockResolvedValue({
      data: [
        {
          event_type: "pick_result", occurred_at: "2026-10-01T00:00:00Z", actor_id: "a2", username: "ben", display_name: "Ben",
          avatar_url: null, post_id: "old", post_caption: "Old prompt", points: 3, match_id: null, game: null, placement: null, raw_score: null, run_mode: null,
        },
      ],
      error: null,
    });
    render(<ActivityFeed initial={full} hasFriends />);

    await user.click(screen.getByRole("button", { name: "Load more" }));
    expect(rpc).toHaveBeenCalledWith("friend_activity", { p_limit: ACTIVITY_PAGE_SIZE, p_before: oldest });
    expect(await screen.findByText(/scored 3 points on/)).toBeInTheDocument();
    expect(screen.queryByRole("button", { name: "Load more" })).not.toBeInTheDocument();
  });
});
