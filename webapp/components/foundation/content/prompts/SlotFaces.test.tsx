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
  render(<YourCalls slots={slots} responses={Object.fromEntries(slots.map((slot) => [slot.id, [slot.options[0].id]]))} collapsible />);

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

  render(<YourCalls slots={[teamSlot]} responses={{ [teamSlot.id]: ["kc"] }} />);

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
  const { container, rerender } = render(<MatchupPicker slot={teamSlot} mode="picker" />);

  for (const logo of container.querySelectorAll("img")) expect(logo.className).not.toContain("grayscale");

  rerender(<MatchupPicker slot={teamSlot} mode="picker" response={["kc"]} />);
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
  expect(target).toHaveClass("ring-fg");
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

const thursday: Slot = {
  id: "thursday",
  label: "Lions @ Bills — winner",
  shape: "pick",
  points: 10,
  options: [
    { id: "det", label: "Lions", teamCode: "DET" },
    { id: "buf", label: "Bills", teamCode: "BUF" },
  ],
};
const sunday: Slot = {
  ...thursday,
  id: "sunday",
  label: "Panthers @ Falcons — winner",
  options: [
    { id: "car", label: "Panthers", teamCode: "CAR" },
    { id: "atl", label: "Falcons", teamCode: "ATL" },
  ],
};

it("marks nothing right or wrong while a pick's game is still ungraded", () => {
  render(<YourCalls slots={[thursday, sunday]} responses={{ thursday: ["buf"], sunday: ["atl"] }} />);

  expect(screen.queryByLabelText("Correct")).not.toBeInTheDocument();
  expect(screen.queryByLabelText("Incorrect")).not.toBeInTheDocument();
});

it("grades each matchup on its own, leaving a pending game unmarked", () => {
  const graded: Slot = { ...thursday, correct: ["buf"] };
  render(<YourCalls slots={[graded, sunday]} responses={{ thursday: ["buf"], sunday: ["atl"] }} />);

  expect(screen.getAllByLabelText("Correct")).toHaveLength(1);
  expect(screen.queryByLabelText("Incorrect")).not.toBeInTheDocument();
});

it("marks a wrong pick on a graded matchup as incorrect", () => {
  const graded: Slot = { ...thursday, correct: ["buf"] };
  render(<YourCalls slots={[graded]} responses={{ thursday: ["det"] }} />);

  expect(screen.getByLabelText("Incorrect")).toBeInTheDocument();
  expect(screen.queryByLabelText("Correct")).not.toBeInTheDocument();
});

const marginSlot: Slot = {
  id: "game",
  label: "Chiefs @ Bills — winner and margin",
  shape: "pick",
  points: 20,
  sourceGameId: "g1",
  options: [
    { id: "kc-u", label: "Chiefs by <7", sublabel: "Wins by 1–6", teamCode: "KC", margin: "under_7" },
    { id: "kc-p", label: "Chiefs by 7+", sublabel: "Wins by 7 or more", teamCode: "KC", margin: "7_plus" },
    { id: "buf-u", label: "Bills by <7", sublabel: "Wins by 1–6", teamCode: "BUF", margin: "under_7" },
    { id: "buf-p", label: "Bills by 7+", sublabel: "Wins by 7 or more", teamCode: "BUF", margin: "7_plus" },
  ],
};

it("lays a Game Picks slot out as four choices and reports the one picked", async () => {
  const onChange = vi.fn();
  render(<MatchupPicker slot={marginSlot} mode="picker" onChange={onChange} />);

  expect(screen.getAllByRole("radio")).toHaveLength(4);
  await userEvent.setup().click(screen.getByText("Bills by 7+"));
  expect(onChange).toHaveBeenCalledWith(["buf-p"]);
});

it("marks a graded Game Picks choice right or wrong", () => {
  const { rerender } = render(<MatchupPicker slot={{ ...marginSlot, correct: ["buf-p"] }} mode="revealed" response={["buf-p"]} />);
  expect(screen.getByLabelText("Correct")).toBeInTheDocument();

  rerender(<MatchupPicker slot={{ ...marginSlot, correct: ["buf-p"] }} mode="revealed" response={["buf-u"]} />);
  expect(screen.getByLabelText("Incorrect")).toBeInTheDocument();

  rerender(<MatchupPicker slot={{ ...marginSlot, correct: [] }} mode="revealed" response={["buf-u"]} />);
  expect(screen.queryByLabelText("Incorrect")).not.toBeInTheDocument();
});
