import { render, screen } from "@testing-library/react";
import userEvent from "@testing-library/user-event";
import { expect, it, vi } from "vitest";

import { GamePickList, YourCalls } from "./SlotFaces";
import type { Slot } from "./types";

const slots: Slot[] = Array.from({ length: 5 }, (_, index) => ({
  id: `game-${index}`,
  label: `Away ${index} @ Home ${index}`,
  shape: "pick",
  points: 1,
  options: [
    { id: `away-${index}`, label: `Away ${index}` },
    { id: `home-${index}`, label: `Home ${index}` },
  ],
}));

it("uses a compact, direct-selection sheet for a multi-game slate", async () => {
  const onChange = vi.fn();
  const user = userEvent.setup();
  render(<GamePickList slots={slots} responses={{}} onChange={onChange} />);

  expect(screen.getByLabelText("Weekly pick sheet")).toHaveTextContent("0/5 picked");
  await user.click(screen.getAllByRole("button", { name: /away/i })[0]);
  expect(onChange).toHaveBeenCalledWith("game-0", ["away-0"]);
});

it("keeps a long revealed ticket compact until expanded", async () => {
  const user = userEvent.setup();
  render(<YourCalls slots={slots} responses={Object.fromEntries(slots.map((slot) => [slot.id, [slot.options[0].id]]))} resolved={false} collapsible />);

  expect(screen.getByText("View all 5 picks")).toBeInTheDocument();
  const finalMatchup = (_: string, element: Element | null) => element?.tagName === "P" && element.textContent === "Away 4 @ Home 4";
  expect(screen.queryByText(finalMatchup)).not.toBeInTheDocument();
  await user.click(screen.getByText("View all 5 picks"));
  expect(screen.getByText(finalMatchup)).toBeInTheDocument();
});
