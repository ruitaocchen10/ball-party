import { readFile } from "node:fs/promises";

import { render, screen } from "@testing-library/react";
import { describe, expect, it } from "vitest";

import { Concealed } from "./Concealed";

describe("Concealed", () => {
  it("uses the reserved dark red surface with full-opacity cream content", () => {
    render(<Concealed label="Hidden score">? ? ?</Concealed>);

    const concealed = screen.getByText("? ? ?");

    expect(concealed).toHaveClass("bg-hidden-ink", "text-panel");
    expect(concealed).not.toHaveClass("bg-hidden");
  });

  it("keeps its diagonal weave subtle enough for the concealed copy to remain legible", async () => {
    const stylesheet = await readFile("app/globals.css", "utf8");

    expect(stylesheet).toMatch(/\.pattern-concealed\s*\{[\s\S]*rgb\(0 0 0 \/ 0\.10\)/);
  });

  it("meets the WCAG AA contrast floor for normal text", async () => {
    const stylesheet = await readFile("app/globals.css", "utf8");
    const concealedSurface = stylesheet.match(/--hidden-ink:\s*(#[0-9a-f]{6})/i)?.[1];
    const creamText = stylesheet.match(/--panel:\s*(#[0-9a-f]{6})/i)?.[1];

    expect(concealedSurface).toBe("#a8291f");
    expect(creamText).toBe("#f4efe4");
    expect(contrastRatio(creamText!, concealedSurface!)).toBeGreaterThanOrEqual(4.5);
  });
});

function contrastRatio(foreground: string, background: string) {
  const [lighter, darker] = [relativeLuminance(foreground), relativeLuminance(background)].sort((a, b) => b - a);
  return (lighter + 0.05) / (darker + 0.05);
}

function relativeLuminance(hex: string) {
  const channels = hex.slice(1).match(/.{2}/g)!.map((channel) => Number.parseInt(channel, 16) / 255);
  const [red, green, blue] = channels.map((channel) =>
    channel <= 0.04045 ? channel / 12.92 : ((channel + 0.055) / 1.055) ** 2.4,
  );

  return 0.2126 * red + 0.7152 * green + 0.0722 * blue;
}
