import { render, screen } from "@testing-library/react";
import userEvent from "@testing-library/user-event";
import { afterEach, describe, expect, it } from "vitest";

import { AnalyticsToggle } from "./AnalyticsToggle";

afterEach(() => {
  document.cookie = "bp_analytics_optout=; Max-Age=0; Path=/";
});

describe("AnalyticsToggle", () => {
  it("is on by default and records an opt-out in a cookie when switched off", async () => {
    const user = userEvent.setup();
    render(<AnalyticsToggle />);

    const checkbox = screen.getByRole("checkbox", { name: /share usage data/i });
    expect(checkbox).toBeChecked();

    await user.click(checkbox);

    expect(checkbox).not.toBeChecked();
    expect(document.cookie).toContain("bp_analytics_optout=1");
  });

  it("shows an existing opt-out and clears it when switched back on", async () => {
    document.cookie = "bp_analytics_optout=1; Path=/";
    const user = userEvent.setup();
    render(<AnalyticsToggle />);

    const checkbox = screen.getByRole("checkbox", { name: /share usage data/i });
    expect(checkbox).not.toBeChecked();

    await user.click(checkbox);

    expect(checkbox).toBeChecked();
    expect(document.cookie).not.toContain("bp_analytics_optout=1");
  });
});
