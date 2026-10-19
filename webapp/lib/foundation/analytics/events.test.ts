import { readFileSync } from "node:fs";
import path from "node:path";

import { describe, expect, it } from "vitest";

import { WEB_EVENT_NAMES } from "@/lib/foundation/analytics/events";

type Contract = { events: { name: string; platforms: string[] }[] };

const contract: Contract = JSON.parse(
  readFileSync(path.resolve(__dirname, "../../../../docs/analytics/events.json"), "utf8"),
);

describe("analytics event contract", () => {
  it("sends exactly the events docs/analytics/events.json lists for web", () => {
    const expected = contract.events.filter((event) => event.platforms.includes("web")).map((event) => event.name);
    expect([...WEB_EVENT_NAMES].sort()).toEqual(expected.sort());
  });

  it("uses snake_case names with no duplicates", () => {
    const names = contract.events.map((event) => event.name);
    expect(new Set(names).size).toBe(names.length);
    for (const name of names) expect(name).toMatch(/^[a-z]+(_[a-z]+)*$/);
  });
});
