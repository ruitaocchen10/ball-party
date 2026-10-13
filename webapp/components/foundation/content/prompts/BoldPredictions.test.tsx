import { fireEvent, render, screen, within } from "@testing-library/react";
import userEvent from "@testing-library/user-event";
import { expect, it, vi } from "vitest";

const refresh = vi.fn();
vi.mock("next/navigation", () => ({
  useRouter: () => ({ refresh }),
}));

import { BoldPredictionsBoard, type BoldPredictionActions } from "./BoldPredictionsBoard";
import { PromptPostComposer, PromptPostFeed } from "./PromptPostUI";
import type { NflScheduleGame } from "@/lib/foundation/content/nfl/schedule";
import type { BoldPrediction, BoldPredictionBoardData } from "@/lib/foundation/content/prompts/boldPredictions";
import type { PlayerResult, PlayerSearch } from "@/lib/foundation/content/prompts/players";
import type { Post } from "@/lib/foundation/content/prompts/types";

const weekGames: NflScheduleGame[] = [
  { id: "2026_05_BUF_KC", season: 2026, week: 5, kickoff: "2099-10-08T00:20:00.000Z", away: "BUF", home: "KC", label: "Bills @ Chiefs", stadium: "Arrowhead", primetime: true },
  { id: "2026_05_SF_LA", season: 2026, week: 5, kickoff: "2099-10-09T17:00:00.000Z", away: "SF", home: "LA", label: "49ers @ Rams", stadium: "SoFi", primetime: false },
];

const mahomes: PlayerResult = { id: "00-0033873", name: "Patrick Mahomes", position: "QB", team: "KC", headshotUrl: null, status: "ACT" };

function boldPost(overrides: Partial<Post> = {}): Post {
  return {
    id: "post-1",
    templateKind: "bold_predictions",
    templateName: "Bold Predictions",
    author: "Ball Party",
    caption: "Make your boldest calls.",
    createdAt: "2099-10-01T12:00:00.000Z",
    promptText: "Week 5 Bold Predictions",
    resolutionCriteria: "Opinion only.",
    lockAt: "2099-10-07T12:00:00.000Z",
    status: "open",
    isOpinion: true,
    slots: [],
    comments: [],
    responseCount: 0,
    predictionCount: 0,
    viewerAnswered: false,
    ...overrides,
  };
}

const lockedPost = () => boldPost({ status: "locked", lockAt: "2026-10-07T12:00:00.000Z" });

function prediction(id: string, body: string, target: BoldPrediction["target"], overrides: Partial<BoldPrediction> = {}): BoldPrediction {
  const merged = { id, author: "Ruitao", authorUsername: "ruitao", isViewer: true, body, target, createdAt: "2099-10-02T12:00:00.000Z", ...overrides };
  return { authorId: `profile-${merged.author}`, ...merged };
}

function data(predictions: BoldPrediction[], players: Record<string, PlayerResult> = {}): BoldPredictionBoardData {
  return { predictions, weekGames, players };
}

function actionsMock(error: string | null = null) {
  return { submit: vi.fn().mockResolvedValue({ error }) } satisfies BoldPredictionActions;
}

/** Every take card keeps its picks behind View take; open them all. */
function openAllTakes() {
  for (const button of screen.getAllByRole("button", { name: "View take" })) fireEvent.click(button);
}

const found = (...players: PlayerResult[]): PlayerSearch => vi.fn(async () => ({ players, error: null }));

/** Writes one prediction into the draft the way a viewer would. */
async function draftPrediction(user: ReturnType<typeof userEvent.setup>, body: string, tag: RegExp | string) {
  await user.type(screen.getByLabelText("Your prediction"), body);
  await user.click(screen.getByRole("button", { name: tag }));
  await user.click(screen.getByRole("button", { name: "Add prediction" }));
}

// --------------------------------------------------------------- entry --

it("counts the drafted slots and the characters", async () => {
  const user = userEvent.setup();
  render(<BoldPredictionsBoard post={boldPost()} data={data([])} viewerCanAnswer actions={actionsMock()} />);

  expect(screen.getByText("0 of 5 used")).toBeInTheDocument();
  expect(screen.getByText("0/280")).toBeInTheDocument();
  await user.type(screen.getByLabelText("Your prediction"), "Hello");
  expect(screen.getByText("5/280")).toBeInTheDocument();

  await user.click(screen.getByRole("button", { name: /Bills @ Chiefs/ }));
  await user.click(screen.getByRole("button", { name: "Add prediction" }));
  expect(screen.getByText("1 of 5 used")).toBeInTheDocument();
});

it("cannot add a prediction without a tag", async () => {
  const user = userEvent.setup();
  render(<BoldPredictionsBoard post={boldPost()} data={data([])} viewerCanAnswer actions={actionsMock()} />);

  await user.type(screen.getByLabelText("Your prediction"), "Mahomes throws for 400");
  expect(screen.getByRole("button", { name: "Add prediction" })).toBeDisabled();

  await user.click(screen.getByRole("button", { name: /Bills @ Chiefs/ }));
  expect(screen.getByRole("button", { name: "Add prediction" })).toBeEnabled();
});

it("cannot add a prediction without text", async () => {
  const user = userEvent.setup();
  render(<BoldPredictionsBoard post={boldPost()} data={data([])} viewerCanAnswer actions={actionsMock()} />);

  await user.click(screen.getByRole("button", { name: /Bills @ Chiefs/ }));
  await user.type(screen.getByLabelText("Your prediction"), "   ");

  expect(screen.getByRole("button", { name: "Add prediction" })).toBeDisabled();
});

it("keeps only one tag: switching tag type drops the previous choice", async () => {
  const user = userEvent.setup();
  render(<BoldPredictionsBoard post={boldPost()} data={data([])} viewerCanAnswer actions={actionsMock()} />);

  await user.type(screen.getByLabelText("Your prediction"), "Bold");
  await user.click(screen.getByRole("button", { name: /Bills @ Chiefs/ }));
  expect(screen.getByRole("button", { name: "Add prediction" })).toBeEnabled();

  await user.click(screen.getByRole("button", { name: "Team" }));
  expect(screen.getByRole("button", { name: "Add prediction" })).toBeDisabled();
});

// ----------------------------------------------------------- lock in --

it("cannot lock in until there is at least one prediction", async () => {
  const user = userEvent.setup();
  render(<BoldPredictionsBoard post={boldPost()} data={data([])} viewerCanAnswer actions={actionsMock()} />);

  expect(screen.getByRole("button", { name: "Lock in" })).toBeDisabled();
  await draftPrediction(user, "Bills win it all", /Bills @ Chiefs/);
  expect(screen.getByRole("button", { name: "Lock in" })).toBeEnabled();
});

it("saves nothing until lock in, then sends every prediction as one response", async () => {
  const user = userEvent.setup();
  const actions = actionsMock();
  render(<BoldPredictionsBoard post={boldPost()} data={data([])} viewerCanAnswer actions={actions} playerSearch={found(mahomes)} />);

  await draftPrediction(user, "  Bills win by 20  ", /49ers @ Rams/);

  await user.type(screen.getByLabelText("Your prediction"), "Packers go 17-0");
  await user.click(screen.getByRole("button", { name: "Team" }));
  await user.click(screen.getByRole("button", { name: "Packers" }));
  await user.click(screen.getByRole("button", { name: "Add prediction" }));

  await user.type(screen.getByLabelText("Your prediction"), "Mahomes throws 5 TDs");
  await user.click(screen.getByRole("button", { name: "Player" }));
  await user.type(screen.getByRole("combobox", { name: "Player tag" }), "mahomes");
  await user.click(await screen.findByRole("option", { name: /Patrick Mahomes/ }));
  await user.click(screen.getByRole("button", { name: "Add prediction" }));

  expect(actions.submit).not.toHaveBeenCalled();
  expect(screen.getAllByRole("listitem")).toHaveLength(3);

  await user.click(screen.getByRole("button", { name: "Lock in" }));

  expect(actions.submit).toHaveBeenCalledTimes(1);
  expect(actions.submit).toHaveBeenCalledWith({
    postId: "post-1",
    predictions: [
      { body: "Bills win by 20", target: { type: "matchup", id: "2026_05_SF_LA" } },
      { body: "Packers go 17-0", target: { type: "team", id: "GB" } },
      { body: "Mahomes throws 5 TDs", target: { type: "player", id: mahomes.id } },
    ],
  });
  expect(refresh).toHaveBeenCalled();
});

it("lets a draft be edited or removed before lock in", async () => {
  const user = userEvent.setup();
  const actions = actionsMock();
  render(<BoldPredictionsBoard post={boldPost()} data={data([])} viewerCanAnswer actions={actions} />);

  await draftPrediction(user, "Bills win it all", /Bills @ Chiefs/);
  await draftPrediction(user, "Throwaway", /49ers @ Rams/);

  await user.click(screen.getByRole("button", { name: "Remove prediction: Throwaway" }));
  expect(screen.queryByText("Throwaway")).not.toBeInTheDocument();

  await user.click(screen.getByRole("button", { name: "Edit prediction: Bills win it all" }));
  const editing = within(screen.getAllByRole("listitem")[0]);
  const field = editing.getByLabelText("Your prediction");
  await user.clear(field);
  await user.type(field, "Chiefs win it all");
  await user.click(editing.getByRole("button", { name: "Team" }));
  await user.click(editing.getByRole("button", { name: "Chiefs" }));
  await user.click(editing.getByRole("button", { name: "Save changes" }));

  await user.click(screen.getByRole("button", { name: "Lock in" }));
  expect(actions.submit).toHaveBeenCalledWith({
    postId: "post-1",
    predictions: [{ body: "Chiefs win it all", target: { type: "team", id: "KC" } }],
  });
});

it("shows the error the backend rejects the response with and keeps the drafts", async () => {
  const user = userEvent.setup();
  render(<BoldPredictionsBoard post={boldPost()} data={data([])} viewerCanAnswer actions={actionsMock("You've already locked in your predictions.")} />);

  await draftPrediction(user, "Too late", /Bills @ Chiefs/);
  await user.click(screen.getByRole("button", { name: "Lock in" }));

  expect(await screen.findByRole("alert")).toHaveTextContent("already locked in");
  expect(screen.getByText("“Too late”")).toBeInTheDocument();
  expect(refresh).not.toHaveBeenCalledWith();
});

it("blocks a sixth prediction in the UI", async () => {
  const user = userEvent.setup();
  render(<BoldPredictionsBoard post={boldPost()} data={data([])} viewerCanAnswer actions={actionsMock()} />);

  for (const n of [1, 2, 3, 4, 5]) await draftPrediction(user, `Call ${n}`, /Bills @ Chiefs/);

  expect(screen.getByText("5 of 5 used")).toBeInTheDocument();
  expect(screen.getByText(/That.s all five/)).toBeInTheDocument();
  expect(screen.queryByLabelText("Your prediction")).not.toBeInTheDocument();
  expect(screen.queryByRole("button", { name: "Add prediction" })).not.toBeInTheDocument();
});

it("asks a signed-out visitor to sign up instead of showing the form", () => {
  render(<BoldPredictionsBoard post={boldPost()} data={data([])} viewerCanAnswer={false} actions={actionsMock()} />);

  expect(screen.getByRole("link", { name: "Sign up" })).toHaveAttribute("href", "/login?next=/prompts/post-1");
  expect(screen.queryByLabelText("Your prediction")).not.toBeInTheDocument();
});

// ---------------------------------------------------- after lock in --

it("shows a locked-in response read-only with everyone else's predictions, before the post locks", () => {
  const mine = [
    prediction("a", "Mine one", { type: "team", id: "BUF" }),
    prediction("b", "Mine two", { type: "team", id: "KC" }),
  ];
  const theirs = prediction("c", "Theirs", { type: "team", id: "GB" }, { author: "Sam", isViewer: false });
  render(<BoldPredictionsBoard post={boldPost()} data={data([theirs, ...mine])} viewerCanAnswer actions={actionsMock()} />);

  expect(screen.getByText("Predictions locked in")).toBeInTheDocument();
  openAllTakes();
  expect(screen.getByText("“Theirs”")).toBeInTheDocument();
  // One card each, with the viewer's first.
  const cards = screen.getAllByRole("article");
  expect(cards).toHaveLength(2);
  expect(within(cards[0]).getByText("“Mine one”")).toBeInTheDocument();
  expect(within(cards[0]).getByText("“Mine two”")).toBeInTheDocument();
  // Final: nothing to edit, remove or add.
  expect(screen.queryByRole("button", { name: /Edit prediction/ })).not.toBeInTheDocument();
  expect(screen.queryByRole("button", { name: /Remove prediction/ })).not.toBeInTheDocument();
  expect(screen.queryByLabelText("Your prediction")).not.toBeInTheDocument();
  expect(screen.queryByRole("button", { name: "Lock in" })).not.toBeInTheDocument();
});

// -------------------------------------------------------- after lock --

const revealed = [
  prediction("a", "Bills beat the Chiefs", { type: "matchup", id: "2026_05_BUF_KC" }, { author: "Ruitao" }),
  prediction("b", "Packers are frauds", { type: "team", id: "GB" }, { author: "Sam", isViewer: false }),
  prediction("c", "Mahomes is MVP", { type: "player", id: mahomes.id }, { author: "Alex", isViewer: false }),
  prediction("d", "Packers lose again", { type: "team", id: "GB" }, { author: "Alex", isViewer: false }),
];

it("reveals everyone's predictions with their tags once the post has locked", () => {
  render(<BoldPredictionsBoard post={lockedPost()} data={data(revealed, { [mahomes.id]: mahomes })} viewerCanAnswer actions={actionsMock()} />);

  expect(screen.getByRole("heading", { name: "Other takes" })).toBeInTheDocument();
  expect(screen.queryByText("4 predictions")).not.toBeInTheDocument();
  // Hidden until asked for, like every other take's picks.
  expect(screen.queryByText("“Packers are frauds”")).not.toBeInTheDocument();
  openAllTakes();
  for (const body of ["Bills beat the Chiefs", "Packers are frauds", "Mahomes is MVP", "Packers lose again"]) {
    expect(screen.getByText(`“${body}”`)).toBeInTheDocument();
  }
  expect(screen.queryByLabelText("Your prediction")).not.toBeInTheDocument();
  // A player tag shows the player's name, a team tag the team's, a matchup tag both clubs.
  const list = screen.getAllByRole("listitem");
  expect(within(list[0]).getByText(/Matchup: Bills @ Chiefs/)).toBeInTheDocument();
  expect(within(list[2]).getByText(/Player: Patrick Mahomes/)).toBeInTheDocument();
  expect(within(list[1]).getByText(/Team: Packers/)).toBeInTheDocument();
});

it("gives each predictions card a comment link into its take and a View take control", () => {
  const post = { ...lockedPost(), comments: [
    { id: "take-sam", authorId: "profile-Sam", author: "Sam", body: "", createdAt: "2026-10-02T12:00:00.000Z", isViewer: false, postedWithPick: true, replies: [] },
  ] };
  render(<BoldPredictionsBoard post={post} data={data(revealed)} viewerCanAnswer actions={actionsMock()} />);

  expect(screen.getByRole("link", { name: "Comment on Sam's take" })).toHaveAttribute("href", "/prompts/post-1/takes/take-sam");
  expect(screen.getAllByRole("button", { name: "View take" })).toHaveLength(3);
});

it("says so when a locked post has no predictions", () => {
  render(<BoldPredictionsBoard post={lockedPost()} data={data([])} viewerCanAnswer actions={actionsMock()} />);

  expect(screen.getByText("Nobody made a prediction before this locked.")).toBeInTheDocument();
});

// ----------------------------------------------------------- card --

it("shows a Bold Predictions card on the feed with its prediction count and a call to action", async () => {
  const user = userEvent.setup();
  const onSelectPost = vi.fn();
  render(<PromptPostFeed posts={[boldPost({ predictionCount: 12 })]} viewerCanAnswer onSelectPost={onSelectPost} />);

  expect(screen.getByRole("heading", { name: "Week 5 Bold Predictions" })).toBeInTheDocument();
  expect(screen.getByText("12 predictions made")).toBeInTheDocument();
  await user.click(screen.getByRole("button", { name: "Make your predictions" }));
  expect(onSelectPost).toHaveBeenCalledWith("post-1");
});

it("points a locked Bold Predictions card at the reveal", () => {
  render(<PromptPostFeed posts={[{ ...lockedPost(), predictionCount: 1 }]} viewerCanAnswer onSelectPost={() => {}} />);

  expect(screen.getByText("1 prediction made")).toBeInTheDocument();
  expect(screen.getByRole("button", { name: "See predictions" })).toBeInTheDocument();
});

// ------------------------------------------------------- composer --

const composerGames: NflScheduleGame[] = [
  { id: "2099_04_A", season: 2099, week: 4, kickoff: "2099-09-30T17:00:00.000Z", away: "BUF", home: "MIA", label: "Bills @ Dolphins", stadium: "Hard Rock", primetime: false },
  { id: "2099_05_B", season: 2099, week: 5, kickoff: "2099-10-08T17:00:00.000Z", away: "KC", home: "BUF", label: "Chiefs @ Bills", stadium: "Highmark", primetime: false },
  { id: "2099_05_C", season: 2099, week: 5, kickoff: "2099-10-07T00:20:00.000Z", away: "SF", home: "LA", label: "49ers @ Rams", stadium: "SoFi", primetime: true },
];

async function chooseBoldWeek(user: ReturnType<typeof userEvent.setup>) {
  render(<PromptPostComposer displayName="Admin" games={composerGames} players={[]} onPublish={vi.fn()} />);
  await user.click(screen.getByRole("button", { name: "Bold Predictions" }));
}

it("offers Bold Predictions as a template and hides the opinion toggle, since it is always opinion", async () => {
  const user = userEvent.setup();
  await chooseBoldWeek(user);

  expect(screen.queryByRole("checkbox", { name: /Opinion prompt/ })).not.toBeInTheDocument();
  expect(screen.getByDisplayValue("NFL Week 4 Bold Predictions")).toBeInTheDocument();
});

it("publishes a Bold Predictions post with no slots, as an opinion, locking before the week's first kickoff", async () => {
  const user = userEvent.setup();
  const onPublish = vi.fn().mockResolvedValue({ id: "new-post" });
  render(<PromptPostComposer displayName="Admin" games={composerGames} players={[]} onPublish={onPublish} />);

  await user.click(screen.getByRole("button", { name: "Bold Predictions" }));
  await user.click(screen.getAllByRole("button", { name: "Publish now" })[0]);

  expect(onPublish).toHaveBeenCalledTimes(1);
  const published = onPublish.mock.calls[0][0];
  expect(published.templateKind).toBe("bold_predictions");
  expect(published.templateName).toBe("Bold Predictions");
  expect(published.promptText).toBe("NFL Week 4 Bold Predictions");
  expect(published.slots).toEqual([]);
  expect(published.isOpinion).toBe(true);
  expect(published.resolutionSource).toBeUndefined();
  // An hour before Week 4's first kickoff.
  expect(new Date(published.lockAt).toISOString()).toBe("2099-09-30T16:00:00.000Z");
});

it("holds Publish back when the lock falls after the week's first kickoff", async () => {
  const user = userEvent.setup();
  await chooseBoldWeek(user);

  const lock = document.querySelector<HTMLInputElement>('input[type="datetime-local"]')!;
  await user.clear(lock);
  await user.type(lock, "2099-10-01T12:00");

  expect(screen.getAllByRole("button", { name: "Publish now" })[0]).toBeDisabled();
  expect(screen.getAllByText(/Locks after Week 3 ends and before Week 4 kicks off/).length).toBeGreaterThan(0);
});
