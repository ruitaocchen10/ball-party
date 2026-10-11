import { fireEvent, render, screen } from "@testing-library/react";
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
    lockAt: "2099-09-20T12:00:00.000Z",
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

  it("leads with friends' takes, above everyone else's", () => {
    const base = post(true);
    const withFriend: Post = { ...base, comments: [...base.comments, { id: "sam", author: "Sam", body: "CMC all day.", createdAt: "2026-09-14T14:00:00.000Z", isViewer: false, isFriend: true, postedWithPick: true, replies: [] }] };
    render(<PromptThread post={withFriend} displayName="Demo Reader" avatarUrl={null} />);

    const friends = screen.getByLabelText("Friend takes");
    const others = screen.getByLabelText("Other takes");
    expect(friends).toHaveTextContent("CMC all day.");
    expect(others).not.toHaveTextContent("CMC all day.");
    expect(friends.compareDocumentPosition(others) & Node.DOCUMENT_POSITION_FOLLOWING).toBeTruthy();
  });

  it("lets a public reader browse takes without exposing an answer form", () => {
    render(<PromptThread post={post(false)} displayName="Player" avatarUrl={null} viewerCanAnswer={false} />);

    expect(screen.getByLabelText("Other takes")).toBeInTheDocument();
    expect(screen.getByText("Bijan has the volume.")).toBeInTheDocument();
    expect(screen.queryByLabelText("Make your picks")).not.toBeInTheDocument();
  });

  it("collapses power rankings ballots — the viewer's own included — until opened", () => {
    const teams = ["Bills", "Chiefs", "Eagles", "Lions", "Ravens"].map((label) => ({ id: label.toLowerCase(), label, teamCode: label.slice(0, 3).toUpperCase() }));
    const ballot: Post = {
      ...post(true),
      templateKind: "power_rankings",
      status: "locked",
      slots: [{ id: "slot", label: "Rank the teams", shape: "rank", pickCount: 5, points: 0, options: teams }],
      viewerResponse: { slot: ["bills", "chiefs", "eagles", "lions", "ravens"] },
      comments: [
        { id: "tasha", author: "Tasha", body: "Boring but defensible.", createdAt: "2026-09-14T13:00:00.000Z", isViewer: false, postedWithPick: true, replies: [], response: { slot: ["ravens", "lions", "eagles", "chiefs", "bills"] } },
        { id: "no-pick", author: "Kai", body: "Just a comment.", createdAt: "2026-09-14T14:00:00.000Z", isViewer: false, postedWithPick: false, replies: [] },
      ],
    };
    render(<PromptThread post={ballot} displayName="Demo Reader" avatarUrl={null} />);

    // Both the viewer's own board and Tasha's start folded away.
    expect(screen.getAllByRole("button", { name: "View take" })).toHaveLength(2);
    expect(screen.queryAllByLabelText("Your power rankings")).toHaveLength(0);

    // Movement is measured against the viewer's own last ballot, which says
    // nothing about Tasha's, so only the viewer's board carries it.
    for (const button of screen.getAllByRole("button", { name: "View take" })) fireEvent.click(button);
    const [yours, tashas] = screen.getAllByLabelText("Your power rankings");
    expect(yours.querySelectorAll("li > span:last-child.bg-\\[\\#f7f5ee\\]").length).toBeGreaterThan(0);
    expect(tashas.querySelectorAll("li > span.bg-\\[\\#f7f5ee\\]")).toHaveLength(0);

    // Hiding the viewer's own board leaves Tasha's open.
    fireEvent.click(screen.getAllByRole("button", { name: "Hide take" })[0]);
    expect(screen.getAllByRole("button", { name: "View take" })).toHaveLength(1);
    expect(screen.getAllByLabelText("Your power rankings")).toHaveLength(1);

    fireEvent.click(screen.getByRole("button", { name: "View take" }));
    expect(screen.getAllByRole("button", { name: "Hide take" })).toHaveLength(2);
    expect(screen.getAllByLabelText("Your power rankings")).toHaveLength(2);
  });

  it("lets a custom prompt's answers — the viewer's own and another reader's — be opened", () => {
    const custom: Post = {
      ...post(true),
      slots: [{ id: "mvp", label: "MVP", shape: "pick", points: 1, options: [{ id: "allen", label: "Josh Allen" }, { id: "hurts", label: "Jalen Hurts" }] }],
      viewerResponse: { mvp: ["allen"] },
      comments: [{ id: "tasha", author: "Tasha", body: "Hurts, easily.", createdAt: "2026-09-14T13:00:00.000Z", isViewer: false, postedWithPick: true, replies: [], response: { mvp: ["hurts"] } }],
    };
    render(<PromptThread post={custom} displayName="Demo Reader" avatarUrl={null} />);

    expect(screen.getAllByRole("button", { name: "View take" })).toHaveLength(2);
  });

  it("shows each author's profile picture on their take", () => {
    const withAvatar: Post = {
      ...post(true),
      comments: [{ id: "tasha", author: "Tasha", authorAvatarUrl: "https://example.test/tasha.png", body: "Hurts, easily.", createdAt: "2026-09-14T13:00:00.000Z", isViewer: false, postedWithPick: false, replies: [] }],
    };
    const { container } = render(<PromptThread post={withAvatar} displayName="Demo Reader" avatarUrl={null} />);

    expect(container.querySelector('img[src="https://example.test/tasha.png"]')).not.toBeNull();
  });

  it("does not render a pick form after an open prompt's deadline passes", () => {
    render(<PromptThread post={{ ...post(false), lockAt: new Date(Date.now() - 1_000).toISOString() }} displayName="Demo Reader" avatarUrl={null} />);

    expect(screen.queryByLabelText("Make your picks")).not.toBeInTheDocument();
    expect(screen.getByText("You did not make picks for this prompt.")).toBeInTheDocument();
  });
});
