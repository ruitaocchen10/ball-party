import { render, waitFor } from "@testing-library/react";
import { describe, expect, it, vi } from "vitest";

const replace = vi.fn();

vi.mock("next/navigation", () => ({
  useRouter: () => ({ replace }),
}));

import { PostGameNavigation } from "@/components/auction/PostGameNavigation";

type RealtimeClient = {
  channel: () => RealtimeClient;
  on: (event: string, filter: unknown, callback: (payload: { new: unknown }) => void) => RealtimeClient;
  subscribe: () => RealtimeClient;
  removeChannel: () => void;
};

describe("PostGameNavigation", () => {
  it("returns an anonymous player to the existing lobby after the host ends a game", async () => {
    let listener: ((payload: { new: unknown }) => void | Promise<void>) | undefined;
    const client: RealtimeClient = {
      channel: () => client,
      on: (_event, _filter, callback) => {
        listener = callback;
        return client;
      },
      subscribe: () => client,
      removeChannel: vi.fn(),
    };
    globalThis.__supabaseMock = client as unknown as typeof globalThis.__supabaseMock;

    render(<PostGameNavigation matchId="match-1" roomCode="ABCD" />);

    await waitFor(() => expect(listener).toBeDefined());
    await listener?.({ new: { choice: "lobby", next_match_id: null } });

    expect(replace).toHaveBeenCalledWith("/lobby/ABCD");
  });
});
