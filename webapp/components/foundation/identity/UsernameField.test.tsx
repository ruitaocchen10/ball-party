import { act, render, screen } from "@testing-library/react";
import { useState } from "react";
import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";

vi.mock("@/app/profile/actions", () => ({ checkUsernameAvailable: vi.fn() }));

import { checkUsernameAvailable } from "@/app/profile/actions";
import { fireEvent } from "@testing-library/react";
import { UsernameField } from "./UsernameField";

function Harness({ initial = "", current, check = true }: { initial?: string; current?: string | null; check?: boolean }) {
  const [value, setValue] = useState(initial);
  return <UsernameField value={value} onChange={setValue} currentUsername={current} checkAvailability={check} />;
}

async function type(value: string) {
  fireEvent.change(screen.getByLabelText(/^Username/), { target: { value } });
  await act(async () => {});
}

describe("UsernameField", () => {
  beforeEach(() => {
    vi.useFakeTimers();
  });
  afterEach(() => {
    vi.useRealTimers();
  });

  it("debounces the availability check and reports the answer", async () => {
    vi.mocked(checkUsernameAvailable).mockResolvedValue({ available: true, error: null });
    render(<Harness />);

    await type("ball_fan");
    expect(screen.getByRole("status")).toHaveTextContent("Checking…");
    expect(checkUsernameAvailable).not.toHaveBeenCalled();

    await act(async () => {
      await vi.advanceTimersByTimeAsync(400);
    });

    expect(checkUsernameAvailable).toHaveBeenCalledTimes(1);
    expect(checkUsernameAvailable).toHaveBeenCalledWith("ball_fan");
    expect(screen.getByRole("status")).toHaveTextContent("Available.");
  });

  it("only asks about the last value typed", async () => {
    vi.mocked(checkUsernameAvailable).mockResolvedValue({ available: false, error: null });
    render(<Harness />);

    await type("abc");
    await act(async () => {
      await vi.advanceTimersByTimeAsync(200);
    });
    await type("abcd");
    await act(async () => {
      await vi.advanceTimersByTimeAsync(400);
    });

    expect(checkUsernameAvailable).toHaveBeenCalledTimes(1);
    expect(checkUsernameAvailable).toHaveBeenCalledWith("abcd");
    expect(screen.getByRole("status")).toHaveTextContent("That username isn’t available.");
  });

  it("gives a format hint without calling the server", async () => {
    render(<Harness />);

    await type("a!");
    await act(async () => {
      await vi.advanceTimersByTimeAsync(1000);
    });

    expect(screen.getByRole("status")).toHaveTextContent(/at least 3/);
    expect(checkUsernameAvailable).not.toHaveBeenCalled();
  });

  it("does not check the player's own current username", async () => {
    render(<Harness initial="me_1" current="me_1" />);

    await act(async () => {
      await vi.advanceTimersByTimeAsync(1000);
    });

    expect(checkUsernameAvailable).not.toHaveBeenCalled();
    expect(screen.getByRole("status")).toHaveTextContent("That’s your current username.");
  });

  it("skips the check entirely when there is no session to ask with", async () => {
    render(<Harness check={false} />);

    await type("fresh_name");
    await act(async () => {
      await vi.advanceTimersByTimeAsync(1000);
    });

    expect(checkUsernameAvailable).not.toHaveBeenCalled();
  });

  it("shows a message when the check itself fails", async () => {
    vi.mocked(checkUsernameAvailable).mockResolvedValue({ available: null, error: "Slow down a little, then try again." });
    render(<Harness />);

    await type("busy_name");
    await act(async () => {
      await vi.advanceTimersByTimeAsync(400);
    });

    expect(screen.getByRole("status")).toHaveTextContent("Slow down a little, then try again.");
  });
});
