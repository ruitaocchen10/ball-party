"use client";

import { useState } from "react";

import { PlayerPicker } from "./PlayerPicker";
import { PlayerPortrait } from "./PlayerPortrait";
import { PROMPT_TICKET_CUT_CORNERS } from "./PromptTicket";
import { MatchupTile, TeamTile, teamSurface } from "./PromptTiles";
import { OptionIcon, SlotFaceC } from "./SlotFaces";
import type { PlayerResult } from "@/lib/foundation/content/prompts/players";
import type { Option, Post, Slot } from "@/lib/foundation/content/prompts/types";

/**
 * Weekly Awards answer inputs. Team and game slots choose from their options
 * like any pick; the three player slots search the directory. A player slot's
 * answer is the player's directory id, not an option id — prompts.submit_response
 * turns it into an option (creating it on the first pick), so `options` on such
 * a slot is only ever the players picked so far.
 */
export function WeeklyAwardsSlots({
  slots,
  responses,
  onChange,
}: {
  slots: Slot[];
  responses: Record<string, string[]>;
  onChange: (slotId: string, response: string[]) => void;
}) {
  // The picker is controlled by a full player, while the draft only keeps the id.
  const [players, setPlayers] = useState<Record<string, PlayerResult | null>>({});

  return (
    <div className="flex flex-col gap-5 px-4 pt-4">
      {slots.map((slot) =>
        slot.playerSearch ? (
          <div key={slot.id}>
            <p className="mb-1.5 font-slab text-sm uppercase text-fg-muted">{slot.label}</p>
            <PlayerPicker
              label={slot.label}
              value={players[slot.id] ?? null}
              onChange={(player) => {
                setPlayers((current) => ({ ...current, [slot.id]: player }));
                onChange(slot.id, player ? [player.id] : []);
              }}
            />
          </div>
        ) : slot.options.every((option) => option.teamCode || option.teamCodes?.length === 2) ? (
          <div key={slot.id}>
            <p className="mb-1.5 font-slab text-sm uppercase text-fg-muted">{slot.label}</p>
            <AwardTiles slot={slot} chosen={responses[slot.id]?.[0]} onChange={(response) => onChange(slot.id, response)} />
          </div>
        ) : (
          <SlotFaceC key={slot.id} slot={slot} disabled={false} response={responses[slot.id] ?? []} onChange={(response) => onChange(slot.id, response)} allResponses={responses} />
        ),
      )}
    </div>
  );
}

/** A team or game slot's options as the same tiles the bold-prediction tag picker and power rankings use; tapping the chosen one again clears it. */
function AwardTiles({ slot, chosen, onChange }: { slot: Slot; chosen: string | undefined; onChange: (response: string[]) => void }) {
  const toggle = (id: string) => onChange(chosen === id ? [] : [id]);
  const matchups = slot.options.some((option) => option.teamCodes);
  return (
    <div role="group" aria-label={slot.label} className={matchups ? "grid gap-2 md:grid-cols-2" : "grid grid-cols-2 gap-1.5 sm:grid-cols-4"}>
      {slot.options.map((option) => {
        const pressed = chosen === option.id;
        const dimmed = chosen !== undefined && !pressed;
        return option.teamCodes ? (
          <MatchupTile key={option.id} away={option.teamCodes[0]} home={option.teamCodes[1]} label={option.label} pressed={pressed} dimmed={dimmed} onClick={() => toggle(option.id)} />
        ) : (
          <TeamTile key={option.id} code={option.teamCode!} name={option.label} pressed={pressed} dimmed={dimmed} onClick={() => toggle(option.id)} />
        );
      })}
    </div>
  );
}

/** A saved Weekly Awards ballot: one team-coloured tile per category, with the share of respondents who chose it once known. */
export function WeeklyAwardsBallot({ post, response }: { post: Post; response: Record<string, string[]> }) {
  return (
    <dl className="grid gap-2.5 px-4 pt-4 sm:grid-cols-2">
      {post.slots.map((slot) => {
        const option = slot.options.find((candidate) => candidate.id === response[slot.id]?.[0]);
        const percent = option ? post.aggregate?.[slot.id]?.[option.id] : undefined;
        const code = option?.teamCode ?? option?.teamCodes?.[0];
        return (
          <div
            key={slot.id}
            style={{ ...PROMPT_TICKET_CUT_CORNERS, ...(code ? teamSurface(code) : {}) }}
            className={`flex min-w-0 flex-col gap-2 border px-3.5 py-3 sm:min-h-32 ${code ? "border-white/20 text-white shadow-[0_4px_10px_rgb(0_0_0/0.22)]" : "border-line bg-surface-raised"}`}
          >
            <dt className={`font-mono text-[10px] tracking-[0.08em] uppercase ${code ? "text-white/70" : "text-fg-muted"}`}>{slot.label}</dt>
            <dd className="flex min-w-0 items-center gap-2.5">
              {option ? (
                slot.playerSearch ? (
                  <PlayerPortrait name={option.label} headshotUrl={option.headshotUrl} className="h-16 w-16 shrink-0 ring-2 ring-white/40 drop-shadow-[0_3px_5px_rgb(0_0_0/0.5)]" />
                ) : (
                  <OptionIcon option={option} className="h-16 w-16 shrink-0 drop-shadow-[0_3px_5px_rgb(0_0_0/0.5)]" />
                )
              ) : null}
              <span className="min-w-0 flex-1 truncate font-slab text-2xl uppercase">{option?.label ?? "—"}</span>
            </dd>
            {percent !== undefined ? <p className={`self-end font-mono text-xs tabular-nums ${code ? "text-white/80" : "text-fg-muted"}`}><span>{percent}%</span></p> : null}
          </div>
        );
      })}
    </dl>
  );
}

const TOP_PICKS_SHOWN = 3;

/** The options chosen most often in a slot, highest vote share first. */
export function topAwardPicks(slot: Slot, shares: Record<string, number> | undefined): { option: Option; percent: number }[] {
  return slot.options
    .map((option) => ({ option, percent: shares?.[option.id] ?? 0 }))
    .filter((pick) => pick.percent > 0)
    .sort((left, right) => right.percent - left.percent || left.option.label.localeCompare(right.option.label))
    .slice(0, TOP_PICKS_SHOWN);
}

/** Per-category results: the top choices and their share of respondents. */
export function WeeklyAwardsResults({ post }: { post: Post }) {
  if (!post.aggregate) return null;
  return (
    <div className="flex flex-col gap-4">
      {post.slots.map((slot) => {
        const picks = topAwardPicks(slot, post.aggregate?.[slot.id]);
        return (
          <div key={slot.id}>
            <p className="mb-1.5 font-mono text-[10px] tracking-[0.1em] text-fg-muted uppercase">{slot.label}</p>
            {picks.length ? (
              <ol className="flex flex-col gap-1.5">
                {picks.map(({ option, percent }) => (
                  <li key={option.id} className="flex items-center gap-2">
                    <OptionIcon option={option} className="h-6 w-6" />
                    <span className="min-w-0 flex-1 truncate font-slab text-sm uppercase">{option.label}</span>
                    <span className="font-mono text-xs text-fg-muted tabular-nums">{percent}%</span>
                  </li>
                ))}
              </ol>
            ) : (
              <p className="text-sm text-fg-muted">No votes yet.</p>
            )}
          </div>
        );
      })}
    </div>
  );
}
