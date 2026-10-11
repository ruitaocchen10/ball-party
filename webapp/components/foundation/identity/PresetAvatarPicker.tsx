"use client";

import Avatar from "boring-avatars";
import { useRef, useState } from "react";

import { createClient } from "@/lib/supabase/client";

// Boring Avatars' neutral defaults. Users can replace every color through the
// native pickers below; no product palette is imposed on their avatar.
const DEFAULT_AVATAR_COLORS = ["#92A1C6", "#146A7C", "#F0AB3D", "#C271B4", "#C20D90"];

const PRESETS = [
  ["Captain", "captain"],
  ["Rookie", "rookie"],
  ["Coach", "coach"],
  ["Ref", "referee"],
  ["MVP", "most-valuable-player"],
  ["Closer", "closer"],
  ["Wildcard", "wildcard"],
  ["Playmaker", "playmaker"],
  ["Gameday", "gameday"],
  ["Overtime", "overtime"],
  ["Rivalry", "rivalry"],
  ["Underdog", "underdog"],
] as const;

/**
 * A small, stable bank of Boring Avatar choices.
 *
 * The picker uploads the selected SVG into the existing avatars bucket, so
 * callers receive a normal public URL and every existing avatar renderer in
 * the app can display the result without learning a new storage format.
 */
export function PresetAvatarPicker({
  userId,
  onSelect,
  onUploadingChange,
}: {
  userId: string;
  onSelect: (avatarUrl: string) => void;
  onUploadingChange: (uploading: boolean) => void;
}) {
  const avatarNodes = useRef(new Map<string, HTMLSpanElement>());
  const [colors, setColors] = useState(DEFAULT_AVATAR_COLORS);
  const [selectedSeed, setSelectedSeed] = useState<string | null>(null);
  const [uploadingSeed, setUploadingSeed] = useState<string | null>(null);
  const [error, setError] = useState<string | null>(null);

  async function choose(seed: string) {
    const svg = avatarNodes.current.get(seed)?.querySelector("svg")?.outerHTML;
    if (!svg) {
      setError("That avatar could not be prepared. Please try another one.");
      return;
    }

    setError(null);
    setUploadingSeed(seed);
    onUploadingChange(true);

    const file = new File([svg], "avatar.svg", { type: "image/svg+xml" });
    const supabase = createClient();
    const path = `${userId}/avatar.svg`;
    const { error: uploadError } = await supabase.storage
      .from("avatars")
      .upload(path, file, { upsert: true, cacheControl: "3600" });

    setUploadingSeed(null);
    onUploadingChange(false);
    if (uploadError) {
      setError("Avatar upload failed. Please try again.");
      return;
    }

    const { data } = supabase.storage.from("avatars").getPublicUrl(path);
    setSelectedSeed(seed);
    // The selected seed makes each preset URL distinct, so switching choices
    // cannot reuse the previous SVG from the browser cache.
    onSelect(`${data.publicUrl}?preset=${encodeURIComponent(seed)}`);
  }

  function setColor(index: number, value: string) {
    setColors((current) => current.map((color, colorIndex) => (colorIndex === index ? value : color)));
    // A selected avatar is a snapshot of the palette at upload time. Clearing
    // its selection makes it clear that the new palette needs to be applied by
    // choosing a design again.
    setSelectedSeed(null);
  }

  return (
    <fieldset className="mt-4">
      <legend className="type-label text-fg-muted">Starter avatars</legend>
      <p className="mt-1 text-[13px] leading-5 text-fg-muted">Customize the palette, then choose a design.</p>
      <div className="mt-3">
        <div className="flex items-center gap-1.5" aria-label="Avatar colors">
          {colors.map((color, index) => (
            <label key={index} className="relative block h-7 w-7 cursor-pointer overflow-hidden rounded-full ring-1 ring-line transition-transform hover:scale-105 focus-within:outline-2 focus-within:outline-offset-2 focus-within:outline-fg">
              <span className="sr-only">Avatar color {index + 1}</span>
              <input
                type="color"
                value={color}
                onChange={(event) => setColor(index, event.target.value)}
                className="absolute -inset-1 h-9 w-9 cursor-pointer border-0 bg-transparent p-0"
              />
            </label>
          ))}
        </div>
      </div>
      <div className="mt-3 grid grid-cols-6 gap-2">
        {PRESETS.map(([label, seed]) => {
          const selecting = uploadingSeed === seed;
          const selected = selectedSeed === seed;
          return (
            <button
              key={seed}
              type="button"
              aria-label={`Choose ${label} avatar`}
              aria-pressed={selected}
              disabled={uploadingSeed !== null}
              onClick={() => choose(seed)}
              className={`relative flex aspect-square items-center justify-center overflow-hidden rounded-full transition-transform hover:scale-105 focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-fg disabled:cursor-wait ${
                selected ? "ring-2 ring-fg ring-offset-2 ring-offset-surface-raised" : "ring-1 ring-line"
              }`}
            >
              <span
                ref={(node) => {
                  if (node) avatarNodes.current.set(seed, node);
                  else avatarNodes.current.delete(seed);
                }}
              >
                <Avatar name={seed} variant="beam" colors={colors} size={48} />
              </span>
              {selecting ? <span className="absolute font-mono text-[8px] text-panel-fg uppercase">Saving</span> : null}
            </button>
          );
        })}
      </div>
      {error ? <p role="alert" className="mt-2 text-sm text-hidden-text">{error}</p> : null}
    </fieldset>
  );
}
