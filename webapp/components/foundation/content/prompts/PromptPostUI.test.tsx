import { render, screen, waitFor, within } from "@testing-library/react";
import { toPng } from "html-to-image";
import userEvent from "@testing-library/user-event";
import { expect, it, vi } from "vitest";

import { PromptPostComposer, PromptPostFeed } from "./PromptPostUI";
import { PromptContext } from "./PromptContext";
import { SharePowerRankingsCard } from "./SharePowerRankingsCard";
import { ShareTakeButton } from "./ShareTakeButton";
import { franchiseLogoUrl, teamLogoCode } from "@/lib/foundation/content/nfl/team-logos";
import type { Post } from "@/lib/foundation/content/prompts/types";

vi.mock("html-to-image", () => ({ toPng: vi.fn().mockResolvedValue("data:image/png;base64,preview") }));

function post(slots: Post["slots"]): Post {
  return {
    id: "post",
    templateKind: "picks",
    templateName: "Picks",
    author: "Ball Party",
    caption: "Make the call.",
    createdAt: "2026-09-01T12:00:00.000Z",
    promptText: "Week 1 picks",
    resolutionCriteria: "Final score wins.",
    lockAt: "2099-09-20T12:00:00.000Z",
    status: "open",
    slots,
    comments: [],
    responseCount: 3,
    viewerAnswered: false,
  };
}

const chiefsAtBills = {
  id: "chiefs-bills",
  label: "Chiefs @ Bills",
  shape: "pick" as const,
  points: 1,
  sourceGameId: "2026_01_KC_BUF",
  options: [
    { id: "kc", label: "Chiefs", teamCode: "KC" },
    { id: "buf", label: "Bills", teamCode: "BUF" },
  ],
};

it("gives a single matchup its own poster treatment and lets a weekly set page through posters", async () => {
  const user = userEvent.setup();
  const gameContexts = [{ id: "2026_01_KC_BUF", stadium: "Highmark Stadium", kickoff: "2026-09-11T00:20:00.000Z", primetime: true }];
  const { rerender } = render(<PromptPostFeed posts={[post([chiefsAtBills])]} viewerCanAnswer onSelectPost={() => {}} gameContexts={gameContexts} />);

  expect(screen.getByTestId("single-game-matchup-preview")).toHaveStyle({ clipPath: expect.stringContaining("polygon") });
  expect(screen.getByText("Primetime")).toBeInTheDocument();
  expect(screen.getByText("Highmark Stadium")).toBeInTheDocument();
  expect(screen.getByText(/8:20 PM/)).toBeInTheDocument();

  rerender(<PromptPostFeed posts={[post([chiefsAtBills, {
    ...chiefsAtBills,
    id: "ravens-bengals",
    label: "Ravens @ Bengals",
    options: [
      { id: "bal", label: "Ravens", teamCode: "BAL" },
      { id: "cin", label: "Bengals", teamCode: "CIN" },
    ],
  }])]} viewerCanAnswer onSelectPost={() => {}} gameContexts={gameContexts} />);

  expect(screen.queryByTestId("single-game-matchup-preview")).not.toBeInTheDocument();
  expect(screen.getByTestId("multi-game-matchup-preview")).toBeInTheDocument();
  expect(screen.getByLabelText("Showing matchup 1 of 2")).toBeInTheDocument();
  expect(screen.getByText("Chiefs")).toBeInTheDocument();

  await user.click(screen.getByRole("button", { name: "Next matchup" }));

  expect(screen.getByLabelText("Showing matchup 2 of 2")).toBeInTheDocument();
  expect(screen.getByText("Ravens")).toBeInTheDocument();
});

it("replaces a completed prompt's timing label with a completion marker", () => {
  render(<PromptPostFeed posts={[{ ...post([chiefsAtBills]), lockAt: "2099-09-20T12:00:00.000Z", viewerAnswered: true, viewerResponse: { "chiefs-bills": ["kc"] } }]} viewerCanAnswer onSelectPost={() => {}} />);

  expect(screen.getByText("Complete")).toBeInTheDocument();
  expect(screen.queryByText(/^Closes /)).not.toBeInTheDocument();
});

it("replaces an unanswered locked prompt's timing label with a locked marker", () => {
  render(<PromptPostFeed posts={[{ ...post([chiefsAtBills]), status: "locked", lockAt: "2026-09-19T12:00:00.000Z" }]} viewerCanAnswer onSelectPost={() => {}} />);

  expect(screen.getByText("Locked")).toBeInTheDocument();
  expect(screen.queryByText(/^\d+[hd] ago$/)).not.toBeInTheDocument();
});

it("does not invite an unanswered prompt past its deadline even while its status remains open", () => {
  render(<PromptPostFeed posts={[{ ...post([chiefsAtBills]), lockAt: new Date(Date.now() - 1_000).toISOString() }]} viewerCanAnswer onSelectPost={() => {}} />);

  expect(screen.getByText("Locked")).toBeInTheDocument();
  expect(screen.queryByRole("button", { name: "Make your picks" })).not.toBeInTheDocument();
  expect(screen.getByRole("button", { name: "See takes" })).toBeInTheDocument();
});

it("replaces an unanswered resolved prompt's timing label with a resolved marker", () => {
  render(<PromptPostFeed posts={[{ ...post([chiefsAtBills]), status: "resolved", lockAt: "2026-09-19T12:00:00.000Z" }]} viewerCanAnswer onSelectPost={() => {}} />);

  expect(screen.getByText("Resolved")).toBeInTheDocument();
  expect(screen.queryByText(/^\d+[hd] ago$/)).not.toBeInTheDocument();
});

it("marking a picks post as opinion publishes it without an auto-resolve source", async () => {
  const user = userEvent.setup();
  const onPublish = vi.fn().mockResolvedValue({ id: "new-post" });
  const games = [{
    id: "2026_01_KC_BUF",
    season: 2026,
    week: 1,
    kickoff: "2099-09-11T00:20:00.000Z",
    away: "KC",
    home: "BUF",
    label: "Chiefs @ Bills",
    stadium: "Highmark Stadium",
    primetime: true,
  }];

  render(<PromptPostComposer displayName="Admin" games={games} players={[]} onPublish={onPublish} />);

  await user.click(screen.getByRole("checkbox", { name: /Opinion prompt/ }));
  await user.click(screen.getAllByRole("button", { name: "Publish now" })[0]);

  expect(onPublish).toHaveBeenCalledTimes(1);
  const published = onPublish.mock.calls[0][0];
  expect(published.isOpinion).toBe(true);
  expect(published.resolutionSource).toBeUndefined();
});

const composerGames = [
  { id: "2026_01_KC_BUF", season: 2026, week: 1, kickoff: "2099-09-11T00:20:00.000Z", away: "KC", home: "BUF", label: "Chiefs @ Bills", stadium: "Highmark Stadium", primetime: true },
  { id: "2026_01_PHI_DAL", season: 2026, week: 1, kickoff: "2099-09-11T17:00:00.000Z", away: "PHI", home: "DAL", label: "Eagles @ Cowboys", stadium: "AT&T Stadium", primetime: false },
];

it("offers Game Picks and Weekly Picks as separate templates and no longer offers Picks", () => {
  render(<PromptPostComposer displayName="Admin" games={composerGames} players={[]} onPublish={vi.fn()} />);

  expect(screen.getByRole("button", { name: "Game Picks" })).toBeInTheDocument();
  expect(screen.getByRole("button", { name: "Weekly Picks" })).toBeInTheDocument();
  expect(screen.queryByRole("button", { name: "Picks" })).not.toBeInTheDocument();
});

it("publishes a single game as game_pick with one slot", async () => {
  const user = userEvent.setup();
  const onPublish = vi.fn().mockResolvedValue({ id: "new-post" });
  render(<PromptPostComposer displayName="Admin" games={composerGames} players={[]} onPublish={onPublish} />);

  await user.click(screen.getAllByRole("button", { name: "Publish now" })[0]);

  const published = onPublish.mock.calls[0][0];
  expect(published.templateKind).toBe("game_pick");
  expect(published.templateName).toBe("Game Picks");
  expect(published.slots).toHaveLength(1);
  expect(published.resolutionSource).toEqual({ provider: "nflverse", rule: "winner" });

  const [slot] = published.slots;
  expect(slot.points).toBe(20);
  expect(slot.options.map((o: { teamCode: string; margin: string; label: string }) => [o.teamCode, o.margin, o.label])).toEqual([
    [composerGames[0].away, "under_7", expect.stringMatching(/ by <7$/)],
    [composerGames[0].away, "7_plus", expect.stringMatching(/ by 7\+$/)],
    [composerGames[0].home, "under_7", expect.stringMatching(/ by <7$/)],
    [composerGames[0].home, "7_plus", expect.stringMatching(/ by 7\+$/)],
  ]);
});

it("keeps Weekly Picks games winner-only at 10 points", async () => {
  const user = userEvent.setup();
  const onPublish = vi.fn().mockResolvedValue({ id: "new-post" });
  render(<PromptPostComposer displayName="Admin" games={composerGames} players={[]} onPublish={onPublish} />);

  await user.click(screen.getByRole("button", { name: "Weekly Picks" }));
  await user.click(screen.getAllByRole("button", { name: "Publish now" })[0]);

  for (const slot of onPublish.mock.calls[0][0].slots) {
    expect(slot.points).toBe(10);
    expect(slot.options).toHaveLength(2);
  }
});

it("publishes a week's slate as weekly_picks with a slot per game", async () => {
  const user = userEvent.setup();
  const onPublish = vi.fn().mockResolvedValue({ id: "new-post" });
  render(<PromptPostComposer displayName="Admin" games={composerGames} players={[]} onPublish={onPublish} />);

  await user.click(screen.getByRole("button", { name: "Weekly Picks" }));
  await user.click(screen.getAllByRole("button", { name: "Publish now" })[0]);

  const published = onPublish.mock.calls[0][0];
  expect(published.templateKind).toBe("weekly_picks");
  expect(published.templateName).toBe("Weekly Picks");
  expect(published.slots).toHaveLength(2);
  expect(published.resolutionSource).toEqual({ provider: "nflverse", rule: "winner" });
});

it("publishes the point value configured for each slot", async () => {
  const user = userEvent.setup();
  const onPublish = vi.fn().mockResolvedValue({ id: "new-post" });
  const games = [{
    id: "2026_01_KC_BUF",
    season: 2026,
    week: 1,
    kickoff: "2099-09-11T00:20:00.000Z",
    away: "KC",
    home: "BUF",
    label: "Chiefs @ Bills",
    stadium: "Highmark Stadium",
    primetime: true,
  }];

  render(<PromptPostComposer displayName="Admin" games={games} players={[]} onPublish={onPublish} />);

  await user.clear(screen.getByLabelText("Chiefs @ Bills — winner and margin points"));
  await user.type(screen.getByLabelText("Chiefs @ Bills — winner and margin points"), "42");
  await user.click(screen.getAllByRole("button", { name: "Publish now" })[0]);

  expect(onPublish).toHaveBeenCalledTimes(1);
  expect(onPublish.mock.calls[0][0].slots[0].points).toBe(42);
});

it("shows the admin's six chosen teams on the Power Rankings cover for every viewer", () => {
  const teams = [["kc", "Chiefs", "KC"], ["buf", "Bills", "BUF"], ["phi", "Eagles", "PHI"], ["bal", "Ravens", "BAL"], ["gb", "Packers", "GB"], ["tb", "Buccaneers", "TB"], ["dal", "Cowboys", "DAL"]];
  const powerSlot = {
    id: "power",
    label: "NFL Power Rankings",
    shape: "rank" as const,
    pickCount: 32,
    points: 1,
    options: teams.map(([id, label, teamCode]) => ({ id, label, teamCode })),
  };
  const powerPost: Post = {
    ...post([powerSlot]),
    templateKind: "power_rankings",
    templateName: "Power rankings",
    coverTeamCodes: ["DAL", "KC", "BUF", "PHI", "BAL", "GB"],
    // A viewer's own ballot and history no longer influence the cover.
    viewerAnswered: true,
    viewerResponse: { power: ["tb", "kc"] },
    previousRankByTeam: { TB: 1 },
  };
  render(<PromptPostFeed posts={[powerPost]} viewerCanAnswer onSelectPost={() => {}} />);

  const board = screen.getByTestId("power-rankings-board");
  const logoSources = [...board.querySelectorAll("img")].map((img) => img.getAttribute("src"));
  expect(logoSources).toEqual(["DAL", "KC", "BUF", "PHI", "BAL", "GB"].map((code) => franchiseLogoUrl(teamLogoCode(code)!)));
  expect(board).not.toHaveTextContent("#1");
});

it("shows the Weekly Awards cover with a single subheadline and no team logos", () => {
  const awardsPost: Post = { ...post([]), templateKind: "weekly_awards", templateName: "Weekly Awards", isOpinion: true };
  render(<PromptPostFeed posts={[awardsPost]} viewerCanAnswer onSelectPost={() => {}} />);

  const cover = screen.getByTestId("weekly-awards-cover");
  expect(cover).toHaveTextContent("Hand out the hardware");
  expect(cover.querySelectorAll("img")).toHaveLength(0);
});

it("shows the Bold Predictions cover with a single subheadline and no team logos", () => {
  const boldPost: Post = { ...post([]), templateKind: "bold_predictions", templateName: "Bold Predictions" };
  render(<PromptPostFeed posts={[boldPost]} viewerCanAnswer onSelectPost={() => {}} />);

  const cover = screen.getByTestId("bold-predictions-cover");
  expect(cover).toHaveTextContent("Call it before it happens");
  expect(cover).not.toHaveTextContent("Private until lock");
  expect(cover.querySelectorAll("img")).toHaveLength(0);
});

it("makes the admin choose exactly six Power Rankings cover teams, in placement order", async () => {
  const user = userEvent.setup();
  const onPublish = vi.fn().mockResolvedValue({ id: "new-post" });
  const games = [{ id: "2026_01_KC_BUF", season: 2026, week: 1, kickoff: "2099-09-11T00:20:00.000Z", away: "KC", home: "BUF", label: "Chiefs @ Bills", stadium: "Highmark Stadium", primetime: true }];
  render(<PromptPostComposer displayName="Admin" games={games} players={[]} onPublish={onPublish} />);

  await user.click(screen.getByRole("button", { name: "Power rankings" }));
  const publish = () => screen.getAllByRole("button", { name: "Publish now" })[0];
  const pool = within(screen.getByText(/Cover art teams/).parentElement!);
  const team = (name: string) => pool.getByRole("button", { name: new RegExp(`^${name}`) });

  for (const name of ["Chiefs", "Bills", "Eagles", "Ravens", "Packers"]) await user.click(team(name));
  expect(publish()).toBeDisabled();

  await user.click(team("Buccaneers"));
  // The picker stops at six; further teams are disabled until one is removed.
  expect(team("Cowboys")).toBeDisabled();
  expect(publish()).toBeEnabled();

  await user.click(publish());
  expect(onPublish.mock.calls[0][0].coverTeamCodes).toEqual(["KC", "BUF", "PHI", "BAL", "GB", "TB"]);
});

it("does not send cover teams for other templates", async () => {
  const user = userEvent.setup();
  const onPublish = vi.fn().mockResolvedValue({ id: "new-post" });
  const games = [{ id: "2026_01_KC_BUF", season: 2026, week: 1, kickoff: "2099-09-11T00:20:00.000Z", away: "KC", home: "BUF", label: "Chiefs @ Bills", stadium: "Highmark Stadium", primetime: true }];
  render(<PromptPostComposer displayName="Admin" games={games} players={[]} onPublish={onPublish} />);

  await user.click(screen.getAllByRole("button", { name: "Publish now" })[0]);
  expect(onPublish.mock.calls[0][0]).not.toHaveProperty("coverTeamCodes");
});

it("shows Power Rankings consensus as the most common top five in the right rail", () => {
  const powerSlot = {
    id: "power",
    label: "NFL Power Rankings",
    shape: "rank" as const,
    pickCount: 32,
    points: 1,
    options: [
      { id: "kc", label: "Chiefs", teamCode: "KC" },
      { id: "buf", label: "Bills", teamCode: "BUF" },
      { id: "phi", label: "Eagles", teamCode: "PHI" },
      { id: "bal", label: "Ravens", teamCode: "BAL" },
      { id: "gb", label: "Packers", teamCode: "GB" },
    ],
  };
  const powerPost: Post = {
    ...post([powerSlot]),
    templateKind: "power_rankings",
    templateName: "Power rankings",
    responseCount: 4,
    powerRankingTopFive: [
      { optionId: "kc", topFiveCount: 4, averageRank: 1.5 },
      { optionId: "buf", topFiveCount: 4, averageRank: 2 },
      { optionId: "phi", topFiveCount: 3, averageRank: 3 },
      { optionId: "bal", topFiveCount: 2, averageRank: 4 },
      { optionId: "gb", topFiveCount: 1, averageRank: 5 },
    ],
  };

  render(<PromptContext post={powerPost} />);

  expect(screen.getByText("Most common top 5")).toBeInTheDocument();
  expect(screen.getByText("Chiefs")).toBeInTheDocument();
  expect(screen.getAllByText("100%")).toHaveLength(2);
  expect(screen.queryByText("How the huddle picked")).not.toBeInTheDocument();
});

it("renders a dedicated share board for a respondent's Power Rankings", () => {
  const powerSlot = {
    id: "power",
    label: "NFL Power Rankings",
    shape: "rank" as const,
    pickCount: 32,
    points: 1,
    options: [
      { id: "kc", label: "Chiefs", teamCode: "KC" },
      { id: "buf", label: "Bills", teamCode: "BUF" },
      { id: "phi", label: "Eagles", teamCode: "PHI" },
    ],
  };
  const powerPost: Post = { ...post([powerSlot]), templateKind: "power_rankings", templateName: "Power rankings" };

  const { container } = render(<SharePowerRankingsCard post={powerPost} responses={{ power: ["kc", "buf", "phi"] }} />);

  expect(screen.getByText("My power rankings")).toBeInTheDocument();
  expect(container.querySelectorAll("img")).toHaveLength(3);
  expect(container.querySelector('[style*="grid-auto-flow: column"]')).toBeInTheDocument();
});

it("regenerates a Power Rankings preview at Reel dimensions when that format is selected", async () => {
  const powerSlot = {
    id: "power",
    label: "NFL Power Rankings",
    shape: "rank" as const,
    pickCount: 32,
    points: 1,
    options: [{ id: "kc", label: "Chiefs", teamCode: "KC" }],
  };
  const powerPost: Post = { ...post([powerSlot]), templateKind: "power_rankings", templateName: "Power rankings" };
  const png = vi.mocked(toPng);
  png.mockClear();

  render(<ShareTakeButton post={powerPost} responses={{ power: ["kc"] }} />);
  await userEvent.click(screen.getByRole("button", { name: /preview a shareable image of your rankings/i }));
  await waitFor(() => expect(png).toHaveBeenCalledTimes(1));
  await userEvent.click(screen.getByRole("button", { name: /instagram reel/i }));

  await waitFor(() => expect(png).toHaveBeenCalledTimes(2));
  const canvas = png.mock.calls[1][0] as HTMLElement;
  expect(canvas.style.height).toBe("960px");
  // The card keeps its 4:5 post size and sits centered on the taller canvas.
  expect((canvas.lastElementChild as HTMLElement).style.height).toBe("675px");
});
