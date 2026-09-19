import type { supabaseMock } from "./factories";

declare global {
  var __supabaseMock: ReturnType<typeof supabaseMock>;
}

export {};
