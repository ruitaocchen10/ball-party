import { act, fireEvent, render, screen } from "@testing-library/react";
import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";

import { useWinnerMoment, type WinnerMomentData } from "./WinnerMoment";

const moment: WinnerMomentData = { faces: [{ name: "Maya", avatarUrl: null }], headline: "Maya wins", detail: "9 correct" };

function Harness({ complete, data }: { complete: boolean; data: WinnerMomentData | null }) {
  return <>{useWinnerMoment(complete, data)}</>;
}

describe("useWinnerMoment", () => {
  beforeEach(() => { vi.useFakeTimers(); });
  afterEach(() => { vi.useRealTimers(); });

  it("plays when the match ends in front of the player, then clears on its own", () => {
    const { rerender } = render(<Harness complete={false} data={null} />);
    rerender(<Harness complete data={moment} />);
    expect(screen.getByRole("alert")).toHaveAccessibleName("Maya wins. 9 correct");
    act(() => { vi.advanceTimersByTime(3000); });
    // exit animation unmounts it
    act(() => { vi.advanceTimersByTime(500); });
    expect(screen.queryByRole("alert")).not.toBeInTheDocument();
  });

  it("waits for the words when the result lands after the last phase", () => {
    const { rerender } = render(<Harness complete={false} data={null} />);
    rerender(<Harness complete data={null} />);
    expect(screen.queryByRole("alert")).not.toBeInTheDocument();
    rerender(<Harness complete data={moment} />);
    expect(screen.getByRole("alert")).toBeInTheDocument();
  });

  it("never replays for a match that was already over when the screen opened", () => {
    render(<Harness complete data={moment} />);
    expect(screen.queryByRole("alert")).not.toBeInTheDocument();
  });

  it("skips on click", () => {
    const { rerender } = render(<Harness complete={false} data={null} />);
    rerender(<Harness complete data={moment} />);
    fireEvent.click(screen.getByRole("alert"));
    act(() => { vi.advanceTimersByTime(500); });
    expect(screen.queryByRole("alert")).not.toBeInTheDocument();
  });
});
