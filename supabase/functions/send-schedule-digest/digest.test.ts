import { assertEquals, assertStringIncludes } from "jsr:@std/assert@1";

import { itemTitle, renderDigest, type DigestItem } from "./digest.ts";

const item = (over: Partial<DigestItem>): DigestItem => ({
  id: "1",
  kind: "weekly_picks",
  game_id: null,
  state: "empty",
  due_at: "2026-10-18T17:00:00Z",
  lock_at: "2026-10-18T17:00:00Z",
  attention: "No prompt written",
  today: false,
  ...over,
});

Deno.test("a game slot is named by its matchup and week", () => {
  assertEquals(itemTitle({ kind: "game_pick", game_id: "2026_05_BUF_KC" }), "Game picks: BUF @ KC (week 5)");
  assertEquals(itemTitle({ kind: "power_rankings", game_id: null }), "Power rankings");
});

Deno.test("today's slots are listed apart from the ones due soon", () => {
  const { subject, text } = renderDigest([item({ today: true, id: "a" }), item({ kind: "weekly_awards", id: "b" })]);
  assertEquals(subject, "2 prompts need attention");
  assertStringIncludes(text, "Opens today and isn't ready:");
  assertStringIncludes(text, "Opens in the next 2 days and isn't ready:");
  assertStringIncludes(text, "No prompt written");
});

Deno.test("one item reads in the singular and links the calendar", () => {
  const { subject, text } = renderDigest([item({})], "https://example.test/admin");
  assertEquals(subject, "1 prompt needs attention");
  assertStringIncludes(text, "https://example.test/admin");
});
