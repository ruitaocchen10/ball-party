import { render, screen } from "@testing-library/react";
import { describe, expect, it, vi } from "vitest";

vi.mock("next/navigation", () => ({
  useRouter: () => ({ refresh: vi.fn() }),
}));

import { PromptThread } from "./PromptThread";
import type { Post } from "@/lib/foundation/content/prompts/types";

function post(viewerAnswered: boolean): Post {
  return {
    id: "week-2",
    templateKind: "stat_leader",
    templateName: "Stat leader",
    author: "Ball Party",
    caption: "Make the call.",
    createdAt: "2026-09-01T12:00:00.000Z",
    promptText: "Who leads the league in rushing yards?",
    resolutionCriteria: "Official Week 18 totals.",
    lockAt: "2026-09-20T12:00:00.000Z",
    status: "open",
    slots: [],
    comments: [
      { id: "mine", author: "Demo Reader", body: "Gibbs is my pick.", createdAt: "2026-09-14T12:00:00.000Z", isViewer: true, postedWithPick: true, replies: [] },
      { id: "tasha", author: "Tasha", body: "Bijan has the volume.", createdAt: "2026-09-14T13:00:00.000Z", isViewer: false, postedWithPick: true, replies: [] },
    ],
    responseCount: 2,
    viewerAnswered,
    viewerResponse: viewerAnswered ? {} : undefined,
  };
}

describe("PromptThread", () => {
  it("withholds other takes until the viewer has made picks", () => {
    const { rerender } = render(<PromptThread post={post(false)} displayName="Demo Reader" avatarUrl={null} />);

    expect(screen.queryByLabelText("Other takes")).not.toBeInTheDocument();
    expect(screen.queryByText("Bijan has the volume.")).not.toBeInTheDocument();

    rerender(<PromptThread post={post(true)} displayName="Demo Reader" avatarUrl={null} />);

    expect(screen.getByLabelText("Other takes")).toBeInTheDocument();
    expect(screen.getByText("Bijan has the volume.")).toBeInTheDocument();
    expect(screen.getByRole("link", { name: "Comment on Tasha's take" })).toHaveAttribute("href", "/prompts/week-2/takes/tasha");
  });
});
