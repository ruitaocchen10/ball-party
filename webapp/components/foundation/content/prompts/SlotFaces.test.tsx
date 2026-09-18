import { fireEvent, render, screen } from "@testing-library/react";
import userEvent from "@testing-library/user-event";
import { useState } from "react";
import { expect, it, vi } from "vitest";

import { GamePickFace, GamePickList, PowerRankingsSlot, YourCalls } from "./SlotFaces";
import { MatchupPicker } from "./MatchupPicker";
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

it("keeps both compact matchup logos in color until a winner is picked", () => {
  const teamSlot: Slot = {
    ...slots[0],
    options: [
      { id: "kc", label: "Chiefs", teamCode: "KC" },
      { id: "buf", label: "Bills", teamCode: "BUF" },
    ],
  };
  const { container, rerender } = render(<MatchupPicker slot={teamSlot} variant="compact" mode="picker" />);

  for (const logo of container.querySelectorAll("img")) expect(logo.className).not.toContain("grayscale");

  rerender(<MatchupPicker slot={teamSlot} variant="compact" mode="picker" response={["kc"]} />);
  const [chiefs, bills] = [...container.querySelectorAll("img")];
  expect(chiefs.className).not.toContain("grayscale");
  expect(bills.className).toContain("grayscale");
});

it("lets a Power Rankings respondent change their own top-N without auto-filling teams", async () => {
  const onChange = vi.fn();
  const user = userEvent.setup();
  const powerSlot: Slot = {
    id: "power",
    label: "NFL Power Rankings",
    shape: "rank",
    pickCount: 32,
    points: 1,
    options: Array.from({ length: 10 }, (_, index) => ({ id: `team-${index}`, label: `Team ${index}`, teamCode: `T${index}` })),
  };

  render(<PowerRankingsSlot slot={powerSlot} response={["team-0", "team-1", "team-2", "team-3", "team-4"]} onChange={onChange} previousRankByTeam={{ T4: 3 }} />);

  expect(screen.getByText("-2")).toBeInTheDocument();
  await user.click(screen.getByRole("button", { name: "Top 10" }));
  expect(onChange).not.toHaveBeenCalled();
  expect(screen.getByLabelText("Your power rankings").querySelector("ol")).toHaveClass("grid-flow-col", "grid-rows-5");
  expect(screen.getAllByText("Choose a team")).toHaveLength(5);

  await user.click(screen.getByRole("button", { name: "Top 32" }));
  expect(screen.getByLabelText("Your power rankings").querySelector("ol")).toHaveClass("grid-flow-col", "sm:grid-rows-8");
  expect(screen.getAllByText("Choose a team")).toHaveLength(27);
});

it("keeps a team at the exact empty rank where it is dropped", async () => {
  const user = userEvent.setup();
  const powerSlot: Slot = {
    id: "power",
    label: "NFL Power Rankings",
    shape: "rank",
    pickCount: 32,
    points: 1,
    options: Array.from({ length: 10 }, (_, index) => ({ id: `team-${index}`, label: `Team ${index}`, teamCode: `T${index}` })),
  };
  function Harness() {
    const [response, setResponse] = useState<string[]>([]);
    return <PowerRankingsSlot slot={powerSlot} response={response} onChange={setResponse} previousRankByTeam={{}} />;
  }

  render(<Harness />);
  await user.click(screen.getByRole("button", { name: "Top 10" }));
  const team = screen.getByRole("button", { name: /add team 6/i });
  const target = screen.getByLabelText("Your power rankings").querySelectorAll("ol > li")[7];
  fireEvent.dragStart(team);
  fireEvent.dragOver(target);
  expect(target).toHaveClass("ring-panel");
  fireEvent.drop(target);

  expect(screen.getByLabelText("Your power rankings").querySelectorAll("ol > li")[7]).toHaveTextContent("Team 6");
});

it("replaces an occupied rank and lets a ranked team return to the available pool", () => {
  const powerSlot: Slot = {
    id: "power",
    label: "NFL Power Rankings",
    shape: "rank",
    pickCount: 32,
    points: 1,
    options: Array.from({ length: 6 }, (_, index) => ({ id: `team-${index}`, label: `Team ${index}`, teamCode: `T${index}` })),
  };
  function Harness() {
    const [response, setResponse] = useState(["team-0"]);
    return <PowerRankingsSlot slot={powerSlot} response={response} onChange={setResponse} previousRankByTeam={{}} />;
  }

  render(<Harness />);
  let rankings = screen.getByLabelText("Your power rankings");
  fireEvent.dragStart(screen.getByRole("button", { name: "Add Team 1" }));
  fireEvent.dragOver(rankings.querySelectorAll("ol > li")[0]);
  fireEvent.drop(rankings.querySelectorAll("ol > li")[0]);

  rankings = screen.getByLabelText("Your power rankings");
  expect(rankings.querySelectorAll("ol > li")[0]).toHaveTextContent("Team 1");
  expect(screen.getByRole("button", { name: "Add Team 0" })).toBeInTheDocument();

  const selected = screen.getByText("Team 1").closest("li")!;
  fireEvent.dragStart(selected);
  const availableArea = screen.getByText("Drop here to remove").parentElement!;
  fireEvent.dragOver(availableArea);
  fireEvent.drop(availableArea);

  expect(screen.getByLabelText("Your power rankings").querySelectorAll("ol > li")[0]).toHaveTextContent("Choose a team");
  expect(screen.getByRole("button", { name: "Add Team 1" })).toBeInTheDocument();
});
