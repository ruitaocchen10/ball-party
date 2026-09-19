import { expect, it } from "vitest";

import { TEAMS } from "./staticOptionPools";

it("contains every NFL team exactly once for league-wide prompt templates", () => {
  expect(TEAMS).toHaveLength(32);
  expect(new Set(TEAMS.map((team) => team.code)).size).toBe(32);
});
