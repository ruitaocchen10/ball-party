import { readFileSync } from "node:fs";
import { join } from "node:path";
import { describe, expect, it } from "vitest";

// The web and iOS apps each keep their own colour tokens so that neither
// build needs anything outside its own folder. This is what keeps the two
// copies from drifting: it reads both and compares them, name for name.

const root = join(process.cwd(), "..");
const css = readFileSync(join(root, "webapp/app/globals.css"), "utf8");
const swift = readFileSync(join(root, "ios/BallParty/Foundation/UIKit/Theme.swift"), "utf8");

const camel = (name: string) => name.replace(/-(\w)/g, (_, c: string) => c.toUpperCase());

/** `--panel-soft: #4c4739;` or `--line: rgb(232 227 214 / 0.13);` → "4C4739" or "E8E3D6@0.13". */
function webColors(): Map<string, string> {
  const rootBlock = css.slice(css.indexOf(":root {"), css.indexOf("}", css.indexOf(":root {")));
  const colors = new Map<string, string>();
  for (const [, name, hex] of rootBlock.matchAll(/^\s*--([a-z-]+):\s*#([0-9a-f]{6});/gim)) {
    colors.set(camel(name), hex.toUpperCase());
  }
  for (const [, name, r, g, b, a] of rootBlock.matchAll(
    /^\s*--([a-z-]+):\s*rgb\((\d+) (\d+) (\d+) \/ ([\d.]+)\);/gim,
  )) {
    const hex = [r, g, b].map((n) => Number(n).toString(16).padStart(2, "0")).join("").toUpperCase();
    colors.set(camel(name), `${hex}@${Number(a)}`);
  }
  return colors;
}

function iosColors(): Map<string, string> {
  const colors = new Map<string, string>();
  for (const [, name, hex, opacity] of swift.matchAll(
    /static let (\w+) = Color\(hex: 0x([0-9A-F]{6})(?:, opacity: ([\d.]+))?\)/g,
  )) {
    colors.set(name, opacity ? `${hex}@${Number(opacity)}` : hex);
  }
  return colors;
}

describe("design tokens", () => {
  const web = webColors();
  const ios = iosColors();

  it("reads a plausible set from each platform", () => {
    expect(web.size).toBeGreaterThan(15);
    expect(ios.size).toBeGreaterThan(15);
  });

  it("has every web colour on iOS with the same value", () => {
    for (const [name, value] of web) {
      expect(ios.get(name), `Theme.${name} is missing or differs from --${name} in globals.css`).toBe(value);
    }
  });

  it("has no iOS colour the web doesn't have", () => {
    for (const name of ios.keys()) {
      expect(web.has(name), `Theme.${name} has no matching --${name} in globals.css`).toBe(true);
    }
  });
});
