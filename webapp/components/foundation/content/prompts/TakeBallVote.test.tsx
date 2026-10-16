import { render, screen } from "@testing-library/react";
import userEvent from "@testing-library/user-event";
import { beforeEach, expect, it, vi } from "vitest";

import { TakeBallVote } from "./TakeBallVote";

const reactToTake = vi.fn();
vi.mock("@/lib/foundation/content/prompts/reactions", () => ({ reactToTake: (...args: unknown[]) => reactToTake(...args) }));
vi.mock("@/lib/supabase/client", () => ({ createClient: () => ({}) }));

beforeEach(() => reactToTake.mockReset());

it("gives a ball, shows the server's net, and takes it back on a second tap", async () => {
  const user = userEvent.setup();
  reactToTake.mockResolvedValueOnce({ net: 5, mine: 1, error: null }).mockResolvedValueOnce({ net: 4, mine: 0, error: null });
  render(<TakeBallVote takeId="t1" initial={{ net: 4, mine: 0, canLike: true, canDislike: true }} />);

  await user.click(screen.getByRole("button", { name: "Give a ball" }));
  expect(reactToTake).toHaveBeenLastCalledWith(expect.anything(), { takeId: "t1", value: 1 });
  expect(await screen.findByLabelText("5 balls")).toBeInTheDocument();
  expect(screen.getByRole("button", { name: "Take back your ball" })).toHaveAttribute("aria-pressed", "true");

  await user.click(screen.getByRole("button", { name: "Take back your ball" }));
  expect(reactToTake).toHaveBeenLastCalledWith(expect.anything(), { takeId: "t1", value: 0 });
  expect(await screen.findByLabelText("4 balls")).toBeInTheDocument();
});

it("puts the count back and says why when the server refuses", async () => {
  const user = userEvent.setup();
  reactToTake.mockResolvedValueOnce({ error: "Only friends can take a ball away." });
  render(<TakeBallVote takeId="t1" initial={{ net: 4, mine: 0, canLike: true, canDislike: true }} />);

  await user.click(screen.getByRole("button", { name: "Take a ball away" }));
  expect(await screen.findByRole("alert")).toHaveTextContent("Only friends can take a ball away.");
  expect(screen.getByLabelText("4 balls")).toBeInTheDocument();
});

it("draws only the thumbs the viewer may use", () => {
  const { rerender } = render(<TakeBallVote takeId="t1" initial={{ net: 9, mine: 0, canLike: true, canDislike: false }} />);
  expect(screen.getByRole("button", { name: "Give a ball" })).toBeInTheDocument();
  expect(screen.queryByRole("button", { name: "Take a ball away" })).not.toBeInTheDocument();

  rerender(<TakeBallVote key="own" takeId="t2" initial={{ net: -2, mine: 0, canLike: false, canDislike: false }} />);
  expect(screen.queryByRole("button")).not.toBeInTheDocument();
  expect(screen.getByLabelText("-2 balls")).toBeInTheDocument();
});
