import { render, screen, waitFor, within } from "@testing-library/react";
import { toPng } from "html-to-image";
import userEvent from "@testing-library/user-event";
import { afterEach, expect, it, vi } from "vitest";

import { PromptPostComposer } from "./PromptPostUI";
import { SharePromptButton } from "./SharePromptButton";
import { SharePromptCard, headlineFontSize } from "./SharePromptCard";
import type { Option } from "@/lib/foundation/content/prompts/types";

vi.mock("html-to-image", () => ({ toPng: vi.fn().mockResolvedValue("data:image/png;base64,preview") }));

const UPLOAD = "https://static.www.nfl.com/image/upload/f_auto,q_auto/league";
const PRIVATE = "https://static.www.nfl.com/image/private/f_auto,q_auto/league";

const candidates: Option[] = [
  { id: "rb-1", label: "Saquon Barkley", sublabel: "PHI", teamCode: "PHI", headshotUrl: `${UPLOAD}/aaa` },
  { id: "rb-2", label: "Derrick Henry", sublabel: "BAL", teamCode: "BAL", headshotUrl: `${PRIVATE}/bbb` },
  { id: "rb-3", label: "Jahmyr Gibbs", sublabel: "DET", teamCode: "DET", headshotUrl: `${UPLOAD}/ccc` },
  { id: "rb-4", label: "Bijan Robinson", sublabel: "ATL", teamCode: "ATL", headshotUrl: `${UPLOAD}/ddd` },
  { id: "rb-5", label: "Breece Hall", sublabel: "NYJ", teamCode: "NYJ", headshotUrl: `${UPLOAD}/eee` },
];

afterEach(() => vi.restoreAllMocks());

it.each([
  [2, "repeat(2, minmax(0, 1fr))", "repeat(1, minmax(0, 1fr))", "w_1100"],
  [3, "repeat(3, minmax(0, 1fr))", "repeat(1, minmax(0, 1fr))", "w_920"],
  [4, "repeat(2, minmax(0, 1fr))", "repeat(2, minmax(0, 1fr))", "w_600"],
])("lays out %i candidates as a tile each, with a resized headshot per player", (count, columns, rows, width) => {
  const { container } = render(<SharePromptCard options={candidates.slice(0, count)} headline="Who leads in rushing?" />);

  const grid = container.querySelector<HTMLElement>('[style*="grid-template-columns"]')!;
  expect(grid.style.gridTemplateColumns).toBe(columns);
  expect(grid.style.gridTemplateRows).toBe(rows);
  expect(grid.children).toHaveLength(count);
  // Each tile has the CDN's resized PNG, never the multi-megabyte original.
  const headshots = container.querySelectorAll(`img[src*="${width}"]`);
  expect(headshots).toHaveLength(count);
  headshots.forEach((img) => expect(img.getAttribute("src")).toContain("f_png,q_auto"));
});

it("asks the question with no answer on it, and shows each candidate's name and team", () => {
  render(<SharePromptCard options={candidates.slice(0, 3)} headline="Who leads in rushing?" />);

  expect(screen.getByRole("heading", { name: "Who leads in rushing?" })).toBeInTheDocument();
  expect(screen.getByText("Pick one")).toBeInTheDocument();
  // First and last names are set apart so the surname can be the big line.
  expect(screen.getByText("Saquon")).toBeInTheDocument();
  expect(screen.getByText("Barkley")).toBeInTheDocument();
  expect(screen.getByText("PHI")).toBeInTheDocument();
});

it("only lays out the first four candidates", () => {
  render(<SharePromptCard options={candidates} headline="Who leads?" />);

  expect(screen.getByText("Robinson")).toBeInTheDocument();
  expect(screen.queryByText("Hall")).not.toBeInTheDocument();
});

it("falls back to initials for a player with no headshot", () => {
  const { container } = render(<SharePromptCard options={[{ ...candidates[0], headshotUrl: "" }, candidates[1]]} headline="Who leads?" />);

  expect(screen.getByText("SB")).toBeInTheDocument();
  expect(container.querySelectorAll('img[src*="f_png"]')).toHaveLength(1);
});

it("keeps the card at 4:5 and only grows the canvas for a reel", () => {
  const { container, rerender } = render(<SharePromptCard options={candidates.slice(0, 2)} headline="Who leads?" />);
  const canvas = () => container.firstElementChild as HTMLElement;
  expect(canvas().style.height).toBe("675px");

  rerender(<SharePromptCard options={candidates.slice(0, 2)} headline="Who leads?" format="reel" />);
  expect(canvas().style.height).toBe("960px");
  expect((canvas().lastElementChild as HTMLElement).style.height).toBe("675px");
});

it("won't make an image for a single candidate, and says why", () => {
  render(<SharePromptButton promptText="Who leads?" options={candidates.slice(0, 1)} />);

  expect(screen.getByRole("button", { name: /preview a shareable image of this prompt/i })).toBeDisabled();
  expect(screen.getByText(/choose at least 2 candidates/i)).toBeInTheDocument();
});

it("waits for the admin to choose the four art players before sharing a bigger pool", () => {
  render(<SharePromptButton promptText="Who leads?" options={candidates} />);

  expect(screen.getByRole("button", { name: /preview a shareable image of this prompt/i })).toBeDisabled();
  expect(screen.getByText(/choose 4 players for the prompt art/i)).toBeInTheDocument();
});

it("shares only the four art players of a bigger pool, in the admin's order", async () => {
  const user = userEvent.setup();
  const png = vi.mocked(toPng);
  png.mockClear();
  // Hall, Henry, Robinson, Barkley are placed 1–4; Gibbs stays in the pool but out of the art.
  const placement: Record<string, number> = { "rb-5": 1, "rb-2": 2, "rb-4": 3, "rb-1": 4 };
  const pool = candidates.map((option) => ({ ...option, coverPosition: placement[option.id] }));
  render(<SharePromptButton promptText="Who leads?" options={pool} />);

  await user.click(screen.getByRole("button", { name: /preview a shareable image of this prompt/i }));
  await waitFor(() => expect(png).toHaveBeenCalledTimes(1));

  const text = (png.mock.calls[0][0] as HTMLElement).textContent ?? "";
  expect(text).not.toContain("Gibbs");
  const positions = ["Hall", "Henry", "Robinson", "Barkley"].map((surname) => text.indexOf(surname));
  expect(positions.every((position) => position >= 0)).toBe(true);
  expect(positions).toEqual([...positions].sort((left, right) => left - right));
});

it("previews the prompt image, regenerates it at reel size, and downloads whichever format is showing", async () => {
  const user = userEvent.setup();
  const png = vi.mocked(toPng);
  png.mockClear();
  const downloads: string[] = [];
  vi.spyOn(HTMLAnchorElement.prototype, "click").mockImplementation(function (this: HTMLAnchorElement) {
    downloads.push(this.download);
  });
  render(<SharePromptButton promptText="Who leads in rushing?" options={candidates.slice(0, 3)} />);

  await user.click(screen.getByRole("button", { name: /preview a shareable image of this prompt/i }));
  await waitFor(() => expect(png).toHaveBeenCalledTimes(1));
  expect((png.mock.calls[0][0] as HTMLElement).style.height).toBe("675px");
  // The preview opens on the prompt text as the headline.
  expect(await screen.findByLabelText("Headline")).toHaveValue("Who leads in rushing?");
  await user.click(screen.getByRole("button", { name: /download/i }));

  await user.click(screen.getByRole("button", { name: /instagram reel/i }));
  await waitFor(() => expect(png).toHaveBeenCalledTimes(2));
  expect((png.mock.calls[1][0] as HTMLElement).style.height).toBe("960px");
  await user.click(await screen.findByRole("button", { name: /download/i }));

  expect(downloads).toEqual(["ball-party-prompt-post.png", "ball-party-prompt-reel.png"]);
});

it("offers Share image in the composer for a pick-one prompt once it has 2–4 candidates", async () => {
  const user = userEvent.setup();
  const players = [
    { id: "rb-1", name: "Saquon Barkley", team: "PHI", position: "RB", headshotUrl: `${UPLOAD}/aaa` },
    { id: "rb-2", name: "Derrick Henry", team: "BAL", position: "RB", headshotUrl: `${PRIVATE}/bbb` },
  ];
  const games = [{ id: "2026_01_KC_BUF", season: 2026, week: 1, kickoff: "2099-09-11T00:20:00.000Z", away: "KC", home: "BUF", label: "Chiefs @ Bills", stadium: "Highmark Stadium", primetime: true }];
  render(<PromptPostComposer displayName="Admin" games={games} players={players} onPublish={vi.fn()} />);
  const share = () => screen.getAllByRole("button", { name: /preview a shareable image of this prompt/i })[0];

  // Other templates don't get it.
  expect(screen.queryByRole("button", { name: /preview a shareable image of this prompt/i })).not.toBeInTheDocument();

  await user.click(screen.getByRole("button", { name: "Pick one out of these" }));
  expect(share()).toBeDisabled();

  await user.click(screen.getByRole("button", { name: "RB" }));
  await user.click(screen.getByRole("button", { name: /Saquon Barkley/ }));
  expect(share()).toBeDisabled();
  await user.click(screen.getByRole("button", { name: /Derrick Henry/ }));
  expect(share()).toBeEnabled();
});

const rushers = [
  { id: "rb-1", name: "Saquon Barkley", team: "PHI", position: "RB", headshotUrl: `${UPLOAD}/aaa` },
  { id: "rb-2", name: "Derrick Henry", team: "BAL", position: "RB", headshotUrl: `${PRIVATE}/bbb` },
  { id: "rb-3", name: "Jahmyr Gibbs", team: "DET", position: "RB", headshotUrl: `${UPLOAD}/ccc` },
  { id: "rb-4", name: "Bijan Robinson", team: "ATL", position: "RB", headshotUrl: `${UPLOAD}/ddd` },
  { id: "rb-5", name: "Breece Hall", team: "NYJ", position: "RB", headshotUrl: `${UPLOAD}/eee` },
  { id: "rb-6", name: "James Cook", team: "BUF", position: "RB", headshotUrl: `${UPLOAD}/fff` },
];
const composerGames = [{ id: "2026_01_KC_BUF", season: 2026, week: 1, kickoff: "2099-09-11T00:20:00.000Z", away: "KC", home: "BUF", label: "Chiefs @ Bills", stadium: "Highmark Stadium", primetime: true }];

async function addCandidates(user: ReturnType<typeof userEvent.setup>, names: string[]) {
  await user.click(screen.getByRole("button", { name: "Pick one out of these" }));
  await user.click(screen.getByRole("button", { name: "RB" }));
  for (const name of names) await user.click(screen.getByRole("button", { name: new RegExp(`${name}.*Add`) }));
}

it("asks which four players the art shows once a pick-one pool outgrows it, and won't publish until they're chosen", async () => {
  const user = userEvent.setup();
  const onPublish = vi.fn().mockResolvedValue({ id: "new-post" });
  render(<PromptPostComposer displayName="Admin" games={composerGames} players={rushers} onPublish={onPublish} />);
  const publish = () => screen.getAllByRole("button", { name: "Publish now" })[0];

  await addCandidates(user, ["Saquon Barkley", "Derrick Henry", "Jahmyr Gibbs", "Bijan Robinson"]);
  // Four fit the art whole: no choice to make.
  expect(screen.queryByText(/prompt art players/i)).not.toBeInTheDocument();
  expect(publish()).toBeEnabled();

  await user.click(screen.getByRole("button", { name: /Breece Hall.*Add/ }));
  const picker = within(screen.getByText(/prompt art players — choose 4 of 5/i).parentElement as HTMLElement);
  expect(publish()).toBeDisabled();
  expect(screen.getAllByRole("button", { name: /preview a shareable image of this prompt/i })[0]).toBeDisabled();

  // Chosen in this order: Hall, Henry, Robinson, Barkley. Gibbs is left out of the art.
  for (const name of ["Breece Hall", "Derrick Henry", "Bijan Robinson", "Saquon Barkley"]) {
    await user.click(picker.getByRole("button", { name: new RegExp(name) }));
  }
  expect(screen.getByText(/prompt art players — choose 4 of 5 \(4\/4\)/i)).toBeInTheDocument();
  expect(picker.getByRole("button", { name: /Jahmyr Gibbs/ })).toBeDisabled();
  expect(publish()).toBeEnabled();
  expect(screen.getAllByRole("button", { name: /preview a shareable image of this prompt/i })[0]).toBeEnabled();

  await user.click(publish());

  const options = onPublish.mock.calls[0][0].slots[0].options as { label: string; coverPosition?: number }[];
  expect(options).toHaveLength(5);
  const placed = options.filter((option) => option.coverPosition !== undefined).sort((left, right) => left.coverPosition! - right.coverPosition!);
  expect(placed.map((option) => option.label)).toEqual(["Breece Hall", "Derrick Henry", "Bijan Robinson", "Saquon Barkley"]);
  expect(options.find((option) => option.label === "Jahmyr Gibbs")?.coverPosition).toBeUndefined();
});

it("takes a player out of the art when they're dropped from the pool", async () => {
  const user = userEvent.setup();
  render(<PromptPostComposer displayName="Admin" games={composerGames} players={rushers} onPublish={vi.fn()} />);

  await addCandidates(user, ["Saquon Barkley", "Derrick Henry", "Jahmyr Gibbs", "Bijan Robinson", "Breece Hall"]);
  const picker = within(screen.getByText(/prompt art players — choose 4 of 5/i).parentElement as HTMLElement);
  await user.click(picker.getByRole("button", { name: /Breece Hall/ }));
  expect(screen.getByText(/choose 4 of 5 \(1\/4\)/i)).toBeInTheDocument();

  // Removing Hall from the candidates (his chip under "Selected candidates") removes him from the art too.
  const selected = within(screen.getByText(/selected candidates/i).parentElement as HTMLElement);
  await user.click(selected.getByRole("button", { name: /Breece Hall/ }));
  expect(screen.queryByText(/prompt art players/i)).not.toBeInTheDocument();
});

it("sizes the headline by how it wraps, not by how many characters it has", () => {
  const short = headlineFontSize("Who leads the league in rushing?");
  // Same length, but two words too long to share a line at the top size, so it must step down.
  const longWords = headlineFontSize("Championship Contender Rankings?");
  const longQuestion = headlineFontSize("Which of these four running backs will finish with the most rushing yards this season?");

  expect(short).toBe(70);
  expect(longWords).toBeLessThan(short);
  expect(longQuestion).toBeLessThan(longWords);
  expect(longQuestion).toBeGreaterThanOrEqual(30);
});
