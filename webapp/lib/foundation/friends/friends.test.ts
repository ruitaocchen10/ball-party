import { describe, expect, it } from "vitest";

import {
  friendErrorMessage,
  friendInvitePath,
  parseRelationship,
  parseSendResult,
} from "./friends";

describe("friends helpers", () => {
  it("treats unknown send results as unavailable", () => {
    expect(parseSendResult("requested")).toBe("requested");
    expect(parseSendResult("blocked")).toBe("unavailable");
    expect(parseSendResult(null)).toBe("unavailable");
  });

  it("parses relationships defensively", () => {
    expect(parseRelationship("incoming")).toBe("incoming");
    expect(parseRelationship("weird")).toBe("none");
  });

  it("maps known errors and hides unknown ones", () => {
    expect(friendErrorMessage("guests_cannot_have_friends")).toBe("Friends need a real account.");
    expect(friendErrorMessage("pg exploded")).toBe("Something went wrong. Try again.");
  });

  it("builds the invite path", () => {
    expect(friendInvitePath("ABC123")).toBe("/friends/invite/ABC123");
  });
});
