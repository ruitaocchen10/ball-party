import { render, screen } from "@testing-library/react";
import userEvent from "@testing-library/user-event";
import { expect, it, vi } from "vitest";

import { GamePickFace, GamePickList, YourCalls } from "./SlotFaces";
import type { Slot } from "@/lib/foundation/content/prompts/types";

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
  expect(screen.queryByLabelText("Away 4 @ Home 4")).not.toBeInTheDocument();
  await user.click(screen.getByText("View all 5 picks"));
  expect(screen.getByLabelText("Away 4 @ Home 4")).toBeInTheDocument();
});

it("renders a saved team pick with its franchise-color treatment", () => {
  const teamSlot: Slot = {
    ...slots[0],
    options: [
      { id: "kc", label: "Chiefs", teamCode: "KC" },
      { id: "buf", label: "Bills", teamCode: "BUF" },
    ],
  };

  render(<YourCalls slots={[teamSlot]} responses={{ [teamSlot.id]: ["kc"] }} resolved={false} />);

  expect(screen.getByLabelText(teamSlot.label)).toBeInTheDocument();
});

it("highlights a featured team pick without throwing", async () => {
  const onChange = vi.fn();
  const user = userEvent.setup();
  const teamSlot: Slot = {
    ...slots[0],
    options: [
      { id: "kc", label: "Chiefs", teamCode: "KC" },
      { id: "buf", label: "Bills", teamCode: "BUF" },
    ],
  };

  render(<GamePickFace slot={teamSlot} disabled={false} response={[]} onChange={onChange} />);
  await user.click(screen.getByRole("button", { name: /chiefs/i }));
  expect(onChange).toHaveBeenCalledWith(["kc"]);
});
