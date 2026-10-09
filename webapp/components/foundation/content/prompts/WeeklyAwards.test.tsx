import { render, screen, within } from "@testing-library/react";
import userEvent from "@testing-library/user-event";
import { useState } from "react";
import { expect, it, vi } from "vitest";

import { PromptPostComposer } from "./PromptPostUI";
import { WeeklyAwardsBallot, WeeklyAwardsResults, topAwardPicks } from "./WeeklyAwards";
import type { Post, Slot } from "@/lib/foundation/content/prompts/types";

vi.mock("@/lib/supabase/client", () => ({ createClient: () => ({}) }));

const team = (code: string) => ({ id: `opt-${code}`, label: code, teamCode: code });
const slots: Slot[] = [
  { id: "s-winner", label: "Biggest winner", shape: "pick", points: 1, options: [team("KC"), team("BUF")] },
  { id: "s-off", label: "Offensive player of the week", shape: "pick", points: 1, playerSearch: true, options: [
    { id: "opt-mahomes", label: "Patrick Mahomes", sublabel: "QB · KC", teamCode: "KC" },
    { id: "opt-allen", label: "Josh Allen", sublabel: "QB · BUF", teamCode: "BUF" },
    { id: "opt-bosa", label: "Nick Bosa", sublabel: "DL · SF", teamCode: "SF" },
  ] },
];

const post = {
  id: "p", templateKind: "weekly_awards", templateName: "Weekly Awards", isOpinion: true, slots,
  aggregate: { "s-winner": { "opt-KC": 70, "opt-BUF": 30 }, "s-off": { "opt-mahomes": 50, "opt-allen": 40, "opt-bosa": 10 } },
} as unknown as Post;

it("ranks a slot's picks by vote share and leaves out options nobody chose", () => {
  const picks = topAwardPicks(slots[1], { "opt-mahomes": 20, "opt-allen": 80, "opt-bosa": 0 });
  expect(picks.map((pick) => pick.option.label)).toEqual(["Josh Allen", "Patrick Mahomes"]);
});

it("shows each category's top choices with their share", () => {
  render(<WeeklyAwardsResults post={post} />);
  expect(screen.getByText("Biggest winner")).toBeInTheDocument();
  const offense = screen.getByText("Offensive player of the week").parentElement!;
  const rows = within(offense).getAllByRole("listitem");
  expect(rows[0]).toHaveTextContent("Patrick Mahomes");
  expect(rows[0]).toHaveTextContent("50%");
});

it("shows the viewer's own ballot with each choice's share", () => {
  render(<WeeklyAwardsBallot post={post} response={{ "s-winner": ["opt-BUF"], "s-off": ["opt-allen"] }} />);
  expect(screen.getByText("Josh Allen")).toBeInTheDocument();
  expect(screen.getByText("40%")).toBeInTheDocument();
  expect(screen.getByText("30%")).toBeInTheDocument();
});

it("answers a player slot with the searched player's directory id, not an option id", async () => {
  vi.resetModules();
  vi.doMock("@/lib/foundation/content/prompts/players", async (importOriginal) => ({
    ...(await importOriginal<typeof import("@/lib/foundation/content/prompts/players")>()),
    searchPlayers: vi.fn(async () => ({
      players: [{ id: "00-0033873", name: "Patrick Mahomes", position: "QB", team: "KC", headshotUrl: null, status: "ACT" }],
      error: null,
    })),
  }));
  const { WeeklyAwardsSlots: Slots } = await import("./WeeklyAwards");
  const seen: Record<string, string[]>[] = [];
  function Harness() {
    const [draft, setDraft] = useState<Record<string, string[]>>({});
    return <Slots slots={slots} responses={draft} onChange={(id, response) => { setDraft((d) => { const next = { ...d, [id]: response }; seen.push(next); return next; }); }} />;
  }
  const user = userEvent.setup();
  render(<Harness />);

  await user.click(screen.getByRole("button", { name: "KC" }));
  await user.type(screen.getByRole("combobox", { name: "Offensive player of the week" }), "mahomes");
  await user.click(await screen.findByRole("option", { name: /Patrick Mahomes/ }));

  expect(seen.at(-1)).toEqual({ "s-winner": ["opt-KC"], "s-off": ["00-0033873"] });
});

it("publishes Weekly Awards as an ungraded opinion post with its six slots in order", async () => {
  const games = [
    { id: "2099_01_KC_BUF", season: 2099, week: 1, kickoff: "2099-09-10T20:00:00.000Z", away: "KC", home: "BUF", label: "Chiefs @ Bills", stadium: "Highmark", primetime: false },
    { id: "2099_01_SF_DAL", season: 2099, week: 1, kickoff: "2099-09-10T23:00:00.000Z", away: "SF", home: "DAL", label: "49ers @ Cowboys", stadium: "AT&T", primetime: false },
  ];
  const onPublish = vi.fn().mockResolvedValue({ id: "new-post" });
  const user = userEvent.setup();
  render(<PromptPostComposer displayName="Admin" games={games} players={[]} onPublish={onPublish} />);

  await user.click(screen.getByRole("button", { name: "Weekly Awards" }));
  expect(screen.queryByRole("checkbox", { name: /Opinion prompt/ })).not.toBeInTheDocument();
  await user.click(screen.getAllByRole("button", { name: "Publish now" })[0]);

  const published = onPublish.mock.calls[0][0];
  expect(published.templateKind).toBe("weekly_awards");
  expect(published.isOpinion).toBe(true);
  expect(published.resolutionSource).toBeUndefined();
  expect(published.slots.map((slot: Slot) => slot.label)).toEqual([
    "Biggest winner", "Biggest loser", "Best game", "Offensive player of the week", "Defensive player of the week", "LVP (least valuable player)",
  ]);
  expect(published.slots.map((slot: Slot) => slot.options.length)).toEqual([32, 32, 2, 0, 0, 0]);
  expect(published.slots.map((slot: Slot) => Boolean(slot.playerSearch))).toEqual([false, false, false, true, true, true]);
});

it("keeps unanswered categories collapsed, opens the next one after a pick, and lets a pick be edited", async () => {
  const three: Slot[] = [...slots, { id: "s-loser", label: "Biggest loser", shape: "pick", points: 1, options: [team("KC"), team("BUF")] }];
  const { WeeklyAwardsSlots: Slots } = await import("./WeeklyAwards");
  function Harness() {
    const [draft, setDraft] = useState<Record<string, string[]>>({});
    return <Slots slots={three} responses={draft} onChange={(id, response) => setDraft((d) => ({ ...d, [id]: response }))} />;
  }
  const user = userEvent.setup();
  render(<Harness />);

  expect(screen.getAllByRole("button", { name: "KC" })).toHaveLength(1);
  expect(screen.getByRole("button", { name: "Pick Biggest loser" })).toBeInTheDocument();

  await user.click(screen.getByRole("button", { name: "KC" }));
  expect(screen.getByRole("button", { name: "Edit Biggest winner" })).toBeInTheDocument();
  expect(screen.getByRole("combobox", { name: "Offensive player of the week" })).toBeInTheDocument();

  await user.click(screen.getByRole("button", { name: "Edit Biggest winner" }));
  expect(screen.getByRole("group", { name: "Biggest winner" })).toBeInTheDocument();
});
