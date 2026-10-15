import { createEvent, fireEvent, render, screen, waitFor } from "@testing-library/react";
import userEvent from "@testing-library/user-event";
import { beforeEach, describe, expect, it, vi } from "vitest";

const rpc = vi.fn();
const refresh = vi.fn();
vi.mock("@/lib/supabase/client", () => ({ createClient: () => ({ rpc }) }));
vi.mock("next/navigation", () => ({ useRouter: () => ({ refresh }) }));

import { ListEditor } from "./ListEditor";
import type { ListKind } from "@/lib/foundation/lists/types";

const power: ListKind = { id: "power_rankings", label: "Power Rankings", itemKind: "team", sizes: [5, 10, 32] };
const me = { displayName: "Demo", avatarUrl: null, username: "demo" };
const saved = ["BUF", "KC", "DET", "PHI", "BAL"];

beforeEach(() => {
  rpc.mockReset();
  refresh.mockReset();
});

describe("ListEditor", () => {
  it("picks a team up and puts it at the row you tap", async () => {
    const user = userEvent.setup();
    render(<ListEditor kind={power} saved={saved} players={{}} openPromptId={null} {...me} />);

    await user.click(screen.getByRole("button", { name: /^4, Philadelphia Eagles/ }));
    expect(screen.getByRole("button", { name: /Philadelphia Eagles, picked up/ })).toHaveAttribute("aria-pressed", "true");

    await user.click(screen.getByRole("button", { name: /^1, Buffalo Bills/ }));

    expect(screen.getByRole("button", { name: /^1, Philadelphia Eagles/ })).toBeInTheDocument();
    expect(screen.getByRole("button", { name: /^2, Buffalo Bills/ })).toBeInTheDocument();
    expect(screen.getByText("4 moved")).toBeInTheDocument();
  });

  /** jsdom has no DataTransfer, so the drag events carry a tiny stand-in. */
  function drag(from: HTMLElement, onto: HTMLElement, item: string) {
    const data = { setData: vi.fn(), getData: () => item, effectAllowed: "" };
    const source = from.closest("li")!;
    const target = onto.closest("li")!;
    fireEvent(source, Object.assign(createEvent.dragStart(source), { dataTransfer: data }));
    fireEvent(target, Object.assign(createEvent.dragOver(target), { dataTransfer: data }));
    fireEvent(target, Object.assign(createEvent.drop(target), { dataTransfer: data }));
  }

  it("moves a row when you drag it onto another place", () => {
    render(<ListEditor kind={power} saved={saved} players={{}} openPromptId={null} {...me} />);

    drag(screen.getByRole("button", { name: /^4, Philadelphia Eagles/ }), screen.getByRole("button", { name: /^1, Buffalo Bills/ }), "PHI");

    expect(screen.getByRole("button", { name: /^1, Philadelphia Eagles/ })).toBeInTheDocument();
    expect(screen.getByRole("button", { name: /^2, Buffalo Bills/ })).toBeInTheDocument();
  });

  it("takes a benched team in when it is dragged onto a place", () => {
    render(<ListEditor kind={power} saved={saved} players={{}} openPromptId={null} {...me} />);

    drag(screen.getByRole("button", { name: /Arizona Cardinals, not ranked/ }), screen.getByRole("button", { name: /^2, Kansas City Chiefs/ }), "ARI");

    expect(screen.getByRole("button", { name: /^2, Arizona Cardinals/ })).toBeInTheDocument();
    expect(screen.getByRole("button", { name: /Baltimore Ravens, not ranked/ })).toBeInTheDocument();
  });

  it("does not drag while a prompt holds the list", () => {
    render(<ListEditor kind={power} saved={saved} players={{}} openPromptId="p1" {...me} />);

    expect(screen.getByRole("button", { name: /^4, Philadelphia Eagles/ }).closest("li")).not.toHaveAttribute("draggable");
  });

  it("moves with the buttons, one step at a time", async () => {
    const user = userEvent.setup();
    render(<ListEditor kind={power} saved={saved} players={{}} openPromptId={null} {...me} />);

    await user.click(screen.getByRole("button", { name: /^2, Kansas City Chiefs/ }));
    await user.click(screen.getByRole("button", { name: "Down" }));

    expect(screen.getByRole("button", { name: /^3, Kansas City Chiefs/, pressed: true })).toBeInTheDocument();
  });

  it("brings a benched team in and drops the last one out", async () => {
    const user = userEvent.setup();
    render(<ListEditor kind={power} saved={saved} players={{}} openPromptId={null} {...me} />);

    await user.click(screen.getByRole("button", { name: /Arizona Cardinals, not ranked/ }));
    await user.click(screen.getByRole("button", { name: /^1, Buffalo Bills/ }));

    expect(screen.getByRole("button", { name: /^1, Arizona Cardinals/ })).toBeInTheDocument();
    expect(screen.queryByRole("button", { name: /^\d+, Baltimore Ravens/ })).not.toBeInTheDocument();
    expect(screen.getByRole("button", { name: /Baltimore Ravens, not ranked/ })).toBeInTheDocument();
  });

  it("saves with a note and shares by default", async () => {
    const user = userEvent.setup();
    rpc.mockResolvedValue({ data: "version-id", error: null });
    render(<ListEditor kind={power} saved={saved} players={{}} openPromptId={null} {...me} />);

    await user.click(screen.getByRole("button", { name: /^2, Kansas City Chiefs/ }));
    await user.click(screen.getByRole("button", { name: "To #1" }));
    await user.type(screen.getByRole("textbox", { name: /Add a take/ }), "Chiefs are back");
    expect(screen.getByRole("checkbox", { name: /Share this update with friends/ })).toBeChecked();
    await user.click(screen.getByRole("button", { name: "Save and share" }));

    await waitFor(() => expect(refresh).toHaveBeenCalled());
    expect(rpc).toHaveBeenCalledWith("save_ranking_list", {
      p_kind: "power_rankings",
      p_items: ["KC", "BUF", "DET", "PHI", "BAL"],
      p_note: "Chiefs are back",
      p_publish: true,
    });
  });

  it("saves quietly when sharing is off", async () => {
    const user = userEvent.setup();
    rpc.mockResolvedValue({ data: "version-id", error: null });
    render(<ListEditor kind={power} saved={saved} players={{}} openPromptId={null} {...me} />);

    await user.click(screen.getByRole("button", { name: /^2, Kansas City Chiefs/ }));
    await user.click(screen.getByRole("button", { name: "Up" }));
    await user.click(screen.getByRole("checkbox", { name: /Share this update/ }));
    await user.click(screen.getByRole("button", { name: "Save" }));

    await waitFor(() => expect(rpc).toHaveBeenCalledWith("save_ranking_list", expect.objectContaining({ p_publish: false })));
  });

  it("says in plain words when the database refuses the save", async () => {
    const user = userEvent.setup();
    rpc.mockResolvedValue({ data: null, error: { message: "edit_limit", details: new Date(Date.now() + 3 * 3600_000 + 60_000).toISOString() } });
    render(<ListEditor kind={power} saved={saved} players={{}} openPromptId={null} {...me} />);

    await user.click(screen.getByRole("button", { name: /^2, Kansas City Chiefs/ }));
    await user.click(screen.getByRole("button", { name: "Up" }));
    await user.click(screen.getByRole("button", { name: "Save and share" }));

    expect(await screen.findByRole("alert")).toHaveTextContent(/save again in 3 hours/);
    expect(refresh).not.toHaveBeenCalled();
  });

  it("sends the player to the open prompt and locks the list", () => {
    render(<ListEditor kind={power} saved={saved} players={{}} openPromptId="post-1" {...me} />);

    expect(screen.getByRole("link", { name: "Go to the prompt" })).toHaveAttribute("href", "/prompts/post-1");
    expect(screen.getByRole("button", { name: /^1, Buffalo Bills/ })).toBeDisabled();
    expect(screen.getByRole("button", { name: "Save and share" })).toBeDisabled();
  });

  it("resizes a team list from the bottom", async () => {
    const user = userEvent.setup();
    render(<ListEditor kind={power} saved={saved} players={{}} openPromptId={null} {...me} />);

    await user.click(screen.getByRole("button", { name: "Top 10" }));

    expect(screen.getByRole("button", { name: /^10, / })).toBeInTheDocument();
    expect(screen.getByRole("list", { name: "Power Rankings, 10 of 10" })).toBeInTheDocument();
  });
});
