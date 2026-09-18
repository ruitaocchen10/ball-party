"use client";

import Avatar from "boring-avatars";

const PALETTES = [
  ["#92A1C6", "#146A7C", "#F0AB3D", "#C271B4", "#C20D90"],
  ["#264653", "#2A9D8F", "#E9C46A", "#F4A261", "#E76F51"],
  ["#355070", "#6D597A", "#B56576", "#E56B6F", "#EAAC8B"],
  ["#606C38", "#283618", "#FEFAE0", "#DDA15E", "#BC6C25"],
  ["#4A4E69", "#9A8C98", "#C9ADA7", "#F2E9E4", "#22223B"],
] as const;
const VARIANTS = ["beam", "bauhaus", "marble", "geometric", "sunset"] as const;

/** A stable, random-looking default for players who have not chosen an image. */
export function GeneratedAvatar({ name, size, className = "" }: { name: string; size: number; className?: string }) {
  const hash = stableHash(name.trim().toLocaleLowerCase() || "player");
  const seed = `ball-party-${hash.toString(36)}`;
  return (
    <Avatar
      aria-hidden="true"
      name={seed}
      variant={VARIANTS[hash % VARIANTS.length]}
      colors={[...PALETTES[Math.floor(hash / VARIANTS.length) % PALETTES.length]]}
      size={size}
      className={`block shrink-0 ${className}`}
    />
  );
}

function stableHash(value: string) {
  let hash = 2166136261;
  for (let index = 0; index < value.length; index += 1) {
    hash ^= value.charCodeAt(index);
    hash = Math.imul(hash, 16777619);
  }
  return hash >>> 0;
}
