import { describe, expect, it, vi } from "vitest";

import type { SeasonResult } from "@/lib/games/qb-season-builder/result";

const { fetchResult, createClient, imageResponse, notFound } = vi.hoisted(() => ({
  fetchResult: vi.fn(),
  createClient: vi.fn(async () => ({}) as never),
  imageResponse: vi.fn(),
  notFound: vi.fn(() => { throw new Error("not found"); }),
}));

vi.mock("@/lib/games/qb-season-builder/read", () => ({ fetchResult }));
vi.mock("@/lib/supabase/server", () => ({ createClient }));
vi.mock("next/og", () => ({ ImageResponse: imageResponse }));
vi.mock("next/navigation", () => ({ notFound }));

import Image from "./opengraph-image";
import { generateMetadata } from "./page";

const result: SeasonResult = {
  matchId: "22222222-2222-2222-2222-222222222222",
  mode: "hidden",
  statLine: { attempts: 598, completions: 412, passYards: 5104, passTds: 44, interceptions: 9, rating: 108.3, rushYards: 312, rushTds: 4 },
  record: { wins: 13, losses: 4 },
  playoffs: { depth: 4, result: "lost_super_bowl" },
  awards: { mvp: true, opoy: false, all_pro: true, pro_bowl: true, sb_mvp: false },
  score: 88.4,
  breakdown: [],
  picks: [],
};

const props = { params: Promise.resolve({ id: result.matchId }), searchParams: Promise.resolve({}) };

describe("QB Season Builder result share routes", () => {
  it("builds metadata and an image for an anonymous reader of a completed result", async () => {
    fetchResult.mockResolvedValue(result);

    const metadata = await generateMetadata(props);
    await Image(props);

    expect(metadata).toMatchObject({
      title: "QB Season Builder",
      description: expect.stringContaining("5,104 pass yards"),
      openGraph: { title: "QB Season Builder", url: `/solo/qb-season-builder/result/${result.matchId}` },
    });
    expect(imageResponse).toHaveBeenCalledOnce();
    expect(fetchResult).toHaveBeenCalledWith({}, result.matchId);
    expect(JSON.stringify(imageResponse.mock.calls[0][0])).not.toContain("BALL PARTY");
  });

  it("does not generate a card for an unknown or unfinished run", async () => {
    fetchResult.mockResolvedValue(null);

    await expect(Image(props)).rejects.toThrow("not found");

    expect(notFound).toHaveBeenCalledOnce();
    expect(imageResponse).not.toHaveBeenCalled();
  });
});
