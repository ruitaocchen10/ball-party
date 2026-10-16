import { describe, expect, it } from "vitest";

import { easternDate } from "./schedule";

describe("calendar days", () => {
  it("puts an instant on its Eastern day, not its UTC day", () => {
    expect(easternDate("2026-10-16T02:30:00Z")).toBe("2026-10-15"); // 10:30pm Thursday in New York
    expect(easternDate("2026-10-16T05:00:00Z")).toBe("2026-10-16");
  });

  it("follows daylight saving, so a slot never lands on the wrong day around the change", () => {
    expect(easternDate("2026-11-01T04:30:00Z")).toBe("2026-11-01"); // 12:30am EDT, before clocks go back
    expect(easternDate("2026-11-02T04:30:00Z")).toBe("2026-11-01"); // 11:30pm EST the same Sunday
  });
});
