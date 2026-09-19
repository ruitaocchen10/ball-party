import { render, screen } from "@testing-library/react";
import { describe, expect, it, vi } from "vitest";

vi.mock("@/lib/auth/actions", () => ({ signOut: vi.fn() }));

import { LobbyTopStrip } from "./LobbyTopStrip";

describe("LobbyTopStrip", () => {
  it("uses the signed-in player's profile image in the compact account control", () => {
    render(
      <LobbyTopStrip
        code="BLTZ"
        displayName="Ava Carter"
        avatarUrl="https://images.example.test/ava.png"
      />,
    );

    expect(document.querySelector("img")).toHaveAttribute(
      "src",
      "https://images.example.test/ava.png",
    );
  });
});
