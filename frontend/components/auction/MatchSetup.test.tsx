import { render, waitFor } from "@testing-library/react";
import { describe, expect, it, vi } from "vitest";

const refresh = vi.fn();

vi.mock("next/navigation", () => ({
  useRouter: () => ({ refresh }),
}));

import { MatchSetup } from "@/components/auction/MatchSetup";

describe("MatchSetup", () => {
  it("re-reads a match once Realtime is ready, recovering a deal update that arrived before subscription", async () => {
    let subscribed: ((status: string) => void) | undefined;
    const client = {
      channel: () => client,
      on: () => client,
      subscribe: (callback?: (status: string) => void) => {
        subscribed = callback;
        return client;
      },
      removeChannel: vi.fn(),
    };
    globalThis.__supabaseMock = client as unknown as typeof globalThis.__supabaseMock;

    render(<MatchSetup matchId="match-1" />);

    await waitFor(() => expect(subscribed).toBeDefined());
    subscribed?.("SUBSCRIBED");

    expect(refresh).toHaveBeenCalledOnce();
  });
});
