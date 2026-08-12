import "@testing-library/jest-dom/vitest";
import { cleanup } from "@testing-library/react";
import { afterEach, vi } from "vitest";

afterEach(() => cleanup());

// The match screen talks to Postgres directly over supabase-js. The tests drive
// the component through props and assert what it renders, so the client is
// replaced wholesale — see test/factories.ts for the RPC spy the suites use.
vi.mock("@/lib/supabase/client", () => ({
  createClient: () => globalThis.__supabaseMock,
  createRealtimeClient: async () => globalThis.__supabaseMock,
}));

// A server action, reached through TopBar -> AccountMenu. Importing it for real
// pulls next/headers into jsdom, which throws.
vi.mock("@/lib/auth/actions", () => ({ signOut: vi.fn() }));

// jsdom implements no layout, so it has no scrollIntoView to call. The board
// strip keeps the live lot centred with it; the scroll itself is not something
// this environment could assert on anyway, so a no-op is the honest stand-in.
if (!Element.prototype.scrollIntoView) Element.prototype.scrollIntoView = vi.fn();
