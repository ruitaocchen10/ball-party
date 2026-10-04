import { render, screen, waitFor } from "@testing-library/react";
import userEvent from "@testing-library/user-event";
import { useState } from "react";
import { expect, it, vi } from "vitest";

import { PlayerPicker } from "./PlayerPicker";
import type { PlayerResult, PlayerSearch } from "@/lib/foundation/content/prompts/players";

const mahomes: PlayerResult = { id: "1", name: "Patrick Mahomes", position: "QB", team: "KC", headshotUrl: null, status: "ACT" };
const bosa: PlayerResult = { id: "2", name: "Nick Bosa", position: "DL", team: "SF", headshotUrl: null, status: "RES" };

function Harness({ search, onPick }: { search: PlayerSearch; onPick?: (p: PlayerResult | null) => void }) {
  const [value, setValue] = useState<PlayerResult | null>(null);
  return <PlayerPicker label="Offensive player" value={value} search={search} onChange={(p) => { setValue(p); onPick?.(p); }} />;
}

const found = (...players: PlayerResult[]): PlayerSearch => vi.fn(async () => ({ players, error: null }));

it("shows matching players with team, position and an injury-status label", async () => {
  const user = userEvent.setup();
  render(<Harness search={found(mahomes, bosa)} />);

  await user.type(screen.getByRole("combobox", { name: "Offensive player" }), "a");

  const options = await screen.findAllByRole("option");
  expect(options).toHaveLength(2);
  expect(options[0]).toHaveTextContent("Patrick Mahomes");
  expect(options[0]).toHaveTextContent("QB · KC");
  expect(options[0]).not.toHaveTextContent("Reserve list");
  expect(options[1]).toHaveTextContent("Reserve list");
});

it("only searches once typing pauses, with the final text", async () => {
  const user = userEvent.setup();
  const search = found(mahomes);
  render(<Harness search={search} />);

  await user.type(screen.getByRole("combobox"), "mahomes");

  await screen.findByRole("option");
  expect(search).toHaveBeenCalledTimes(1);
  expect(search).toHaveBeenCalledWith("mahomes");
});

it("picks the highlighted player with the keyboard", async () => {
  const user = userEvent.setup();
  const onPick = vi.fn();
  render(<Harness search={found(mahomes, bosa)} onPick={onPick} />);

  await user.type(screen.getByRole("combobox"), "a");
  await screen.findAllByRole("option");
  await user.keyboard("{ArrowDown}{Enter}");

  expect(onPick).toHaveBeenCalledWith(bosa);
  expect(screen.queryByRole("combobox")).not.toBeInTheDocument();
  expect(screen.getByText("Nick Bosa")).toBeInTheDocument();
});

it("picks a player by clicking, and lets the choice be cleared", async () => {
  const user = userEvent.setup();
  render(<Harness search={found(mahomes)} />);

  await user.type(screen.getByRole("combobox"), "m");
  await user.click(await screen.findByRole("option"));
  await user.click(screen.getByRole("button", { name: "Change Offensive player" }));

  expect(screen.getByRole("combobox")).toHaveValue("");
});

it("closes the list on Escape", async () => {
  const user = userEvent.setup();
  render(<Harness search={found(mahomes)} />);

  await user.type(screen.getByRole("combobox"), "m");
  await screen.findByRole("option");
  await user.keyboard("{Escape}");

  expect(screen.queryByRole("option")).not.toBeInTheDocument();
});

it("says so when nothing matches", async () => {
  const user = userEvent.setup();
  render(<Harness search={found()} />);

  await user.type(screen.getByRole("combobox"), "zzz");

  expect(await screen.findByText("No players found.")).toBeInTheDocument();
});

it("shows a loading state while the search is in flight", async () => {
  const user = userEvent.setup();
  let finish: ((v: { players: PlayerResult[]; error: null }) => void) | null = null;
  const search: PlayerSearch = () => new Promise((resolve) => { finish = resolve; });
  render(<Harness search={search} />);

  await user.type(screen.getByRole("combobox"), "m");
  expect(await screen.findByText("Searching…")).toBeInTheDocument();
  await waitFor(() => expect(finish).not.toBeNull());

  finish!({ players: [mahomes], error: null });
  expect(await screen.findByRole("option")).toBeInTheDocument();
  expect(screen.queryByText("Searching…")).not.toBeInTheDocument();
});

it("shows an error, and recovers on the next search", async () => {
  const user = userEvent.setup();
  const search = vi.fn<PlayerSearch>()
    .mockResolvedValueOnce({ players: [], error: "Sign in to answer." })
    .mockResolvedValueOnce({ players: [mahomes], error: null });
  render(<Harness search={search} />);

  await user.type(screen.getByRole("combobox"), "m");
  expect(await screen.findByRole("alert")).toHaveTextContent("Sign in to answer.");

  await user.type(screen.getByRole("combobox"), "a");
  expect(await screen.findByRole("option")).toBeInTheDocument();
  await waitFor(() => expect(screen.queryByText("Sign in to answer.")).not.toBeInTheDocument());
});

it("ignores a slow response that arrives after a newer search", async () => {
  const user = userEvent.setup();
  const resolvers: Array<(v: { players: PlayerResult[]; error: null }) => void> = [];
  const search: PlayerSearch = () => new Promise((resolve) => { resolvers.push(resolve); });
  render(<Harness search={search} />);

  await user.type(screen.getByRole("combobox"), "m");
  await waitFor(() => expect(resolvers).toHaveLength(1));
  await user.type(screen.getByRole("combobox"), "a");
  await waitFor(() => expect(resolvers).toHaveLength(2));

  resolvers[1]({ players: [bosa], error: null });
  expect(await screen.findByRole("option")).toHaveTextContent("Nick Bosa");
  resolvers[0]({ players: [mahomes], error: null });

  await waitFor(() => expect(screen.getAllByRole("option")).toHaveLength(1));
  expect(screen.getByRole("option")).toHaveTextContent("Nick Bosa");
});
