import { render, waitFor } from "@testing-library/react";
import { describe, expect, it, vi } from "vitest";

const refresh = vi.fn();
const replace = vi.fn();

vi.mock("next/navigation", () => ({
  useRouter: () => ({ refresh, replace }),
}));

import { LobbyRealtime } from "@/components/lobby/LobbyRealtime";

describe("LobbyRealtime", () => {
  it("returns every open lobby tab home when the host closes the room", async () => {
    let lobbyListener: ((payload: { new: unknown }) => void) | undefined;
    const client = {
      channel: () => client,
      on: (_event: string, filter: { table: string }, callback: (payload: { new: unknown }) => void) => {
        if (filter.table === "lobbies") lobbyListener = callback;
        return client;
      },
      subscribe: () => client,
      removeChannel: vi.fn(),
      rpc: vi.fn(),
    };
    globalThis.__supabaseMock = client as unknown as typeof globalThis.__supabaseMock;

    render(<LobbyRealtime lobbyId="lobby-1" />);

    await waitFor(() => expect(lobbyListener).toBeDefined());
    lobbyListener?.({ new: { closed_at: "2026-08-13T16:00:00.000Z" } });

    expect(replace).toHaveBeenCalledWith("/");
    expect(refresh).not.toHaveBeenCalled();
  });
});
