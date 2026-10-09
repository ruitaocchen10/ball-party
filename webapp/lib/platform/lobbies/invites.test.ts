import { describe, expect, it } from "vitest";

import { inviteErrorMessage, inviteRoomSummary, isInviteSettled, parseInviteResult } from "./invites";

describe("parseInviteResult", () => {
  it("passes through every result the RPC returns", () => {
    for (const result of ["invited", "already_invited", "already_in_room", "room_full", "unavailable"]) {
      expect(parseInviteResult(result)).toBe(result);
    }
  });

  it("treats anything unexpected as unavailable", () => {
    expect(parseInviteResult("teapot")).toBe("unavailable");
    expect(parseInviteResult(null)).toBe("unavailable");
  });
});

describe("isInviteSettled", () => {
  it("only lets the viewer retry an unavailable friend", () => {
    expect(isInviteSettled("invited")).toBe(true);
    expect(isInviteSettled("room_full")).toBe(true);
    expect(isInviteSettled("unavailable")).toBe(false);
  });
});

describe("inviteErrorMessage", () => {
  it("explains a dead invite and hides unknown server text", () => {
    expect(inviteErrorMessage("invite_not_found")).toBe("That invite is no longer available.");
    expect(inviteErrorMessage("lobby_full")).toBe("That room is already full.");
    expect(inviteErrorMessage("some internal sql failure")).toBe("Something went wrong. Try again.");
  });
});

describe("inviteRoomSummary", () => {
  it("names the game when one is picked", () => {
    expect(inviteRoomSummary("Higher or Lower", 2)).toBe("Higher or Lower · 2 of 4 players");
    expect(inviteRoomSummary(null, 1)).toBe("1 of 4 players");
  });
});
