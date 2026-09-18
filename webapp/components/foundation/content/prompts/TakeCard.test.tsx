import { render, screen } from "@testing-library/react";
import userEvent from "@testing-library/user-event";
import { expect, it } from "vitest";

import { TakeCard } from "./TakeCard";

const comment = {
  id: "take-1",
  author: "Demo Reader",
  body: "Ravens, Eagles, Chargers. Feeling good about this ticket.",
  createdAt: "2026-09-14T12:00:00.000Z",
  isViewer: true,
  postedWithPick: true,
  replies: [{
    id: "reply-1",
    author: "Tasha",
    body: "The Ravens call is the one I disagree with.",
    createdAt: "2026-09-14T13:00:00.000Z",
    isViewer: false,
    postedWithPick: false,
    replies: [],
  }],
};

it("makes take copy prominent and routes discussion through the comment icon", async () => {
  const user = userEvent.setup();
  render(
    <TakeCard comment={comment} commentHref="/prompts/week-2/takes/take-1" collapsedByDefault>
      <p>Revealed ticket</p>
    </TakeCard>,
  );

  expect(screen.getByText(comment.body)).toHaveClass("text-lg", "leading-7", "font-medium");
  expect(screen.getByRole("link", { name: "Comment on Demo Reader's take" })).toHaveAttribute("href", "/prompts/week-2/takes/take-1");
  expect(screen.getByText("1")).toBeInTheDocument();
  expect(screen.queryByText("Revealed ticket")).not.toBeInTheDocument();

  await user.click(screen.getByRole("button", { name: /view take/i }));

  expect(screen.getByText("Revealed ticket")).toBeInTheDocument();
  expect(screen.getByRole("button", { name: /hide take/i })).toBeInTheDocument();
});
