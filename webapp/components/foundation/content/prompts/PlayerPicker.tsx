"use client";

import { useEffect, useId, useMemo, useRef, useState } from "react";

import { Check, Search } from "lucide-react";

import { AnchoredList } from "@/components/foundation/ui-kit/AnchoredList";
import { PlayerPortrait } from "./PlayerPortrait";
import { PROMPT_TICKET_CUT_CORNERS } from "./PromptTicket";
import { teamPrimaryColor } from "@/lib/foundation/content/nfl/team-logos";
import { createClient } from "@/lib/supabase/client";
import { playerStatusLabel, searchPlayers, type PlayerResult, type PlayerSearch } from "@/lib/foundation/content/prompts/players";

const DEBOUNCE_MS = 200;

type Props = {
  /** The chosen player, or null. Controlled: the parent owns the selection. */
  value: PlayerResult | null;
  onChange: (player: PlayerResult | null) => void;
  label: string;
  /** Overrides the directory lookup; defaults to prompts.search_players. */
  search?: PlayerSearch;
  disabled?: boolean;
};

type Status = "idle" | "loading" | "error" | "done";

/**
 * Type-ahead over the NFL player directory. Knows nothing about any prompt
 * kind — Weekly Awards and Bold Predictions both hand it a value and take back
 * a PlayerResult. Follows the ARIA combobox pattern: focus stays in the input,
 * arrows move an active option, Enter picks it, Escape closes the list.
 */
export function PlayerPicker({ value, onChange, label, search, disabled }: Props) {
  const supabase = useMemo(() => (search ? null : createClient()), [search]);
  const run = useMemo<PlayerSearch>(() => search ?? ((query) => searchPlayers(supabase!, query)), [search, supabase]);
  const listId = useId();
  const [query, setQuery] = useState("");
  const [open, setOpen] = useState(false);
  const [status, setStatus] = useState<Status>("idle");
  const [results, setResults] = useState<PlayerResult[]>([]);
  const [error, setError] = useState<string | null>(null);
  const [active, setActive] = useState(0);
  const anchorRef = useRef<HTMLDivElement>(null);
  // Bumped per request so a slow early response can't overwrite a later one.
  const latest = useRef(0);

  useEffect(() => {
    const request = ++latest.current;
    if (!query.trim()) return;
    const timer = setTimeout(async () => {
      const outcome = await run(query).catch(() => ({ players: [], error: "Couldn't search players. Try again." }));
      if (request !== latest.current) return;
      setResults(outcome.players);
      setError(outcome.error);
      setActive(0);
      setStatus(outcome.error ? "error" : "done");
    }, DEBOUNCE_MS);
    return () => clearTimeout(timer);
  }, [query, run]);

  const pick = (player: PlayerResult) => {
    onChange(player);
    setQuery("");
    setOpen(false);
  };

  if (value) {
    // The same tile language as a chosen team: the club's colors behind the player.
    return (
      <div
        style={{ ...PROMPT_TICKET_CUT_CORNERS, background: `linear-gradient(135deg, ${teamPrimaryColor(value.team) ?? "#252722"}, #171914 72%)` }}
        className="relative flex items-center gap-3 overflow-hidden border border-white/25 px-3 py-2 text-white shadow-[0_4px_10px_rgb(0_0_0/0.28)]"
      >
        <PlayerPortrait name={value.name} headshotUrl={value.headshotUrl} className="h-11 w-11 ring-2 ring-white/70" />
        <PlayerSummary player={value} onDark />
        <Check aria-hidden className="h-4 w-4 shrink-0 text-white" strokeWidth={3} />
        {disabled ? null : (
          <button type="button" aria-label={`Change ${label}`} onClick={() => onChange(null)} className="ml-auto cursor-pointer type-label text-white/80 underline underline-offset-2 hover:text-white">
            Change
          </button>
        )}
      </div>
    );
  }

  const showList = open && query.trim() !== "";
  const optionId = (index: number) => `${listId}-option-${index}`;

  return (
    <div>
      <div ref={anchorRef} className="relative">
        <Search aria-hidden className="pointer-events-none absolute top-1/2 left-3 h-4 w-4 -translate-y-1/2 text-fg-muted" />
        <input
          type="text"
          role="combobox"
          aria-label={label}
          aria-expanded={showList}
          aria-controls={showList ? listId : undefined}
          aria-autocomplete="list"
          aria-activedescendant={showList && results[active] ? optionId(active) : undefined}
          autoComplete="off"
          disabled={disabled}
          placeholder="Search players"
          value={query}
          onChange={(event) => { setQuery(event.target.value); setOpen(true); setStatus(event.target.value.trim() ? "loading" : "idle"); }}
          onFocus={() => setOpen(true)}
          onBlur={() => setOpen(false)}
          onKeyDown={(event) => {
            if (event.key === "ArrowDown") { event.preventDefault(); setOpen(true); setActive((i) => Math.min(i + 1, results.length - 1)); }
            else if (event.key === "ArrowUp") { event.preventDefault(); setActive((i) => Math.max(i - 1, 0)); }
            else if (event.key === "Enter" && showList && results[active]) { event.preventDefault(); pick(results[active]); }
            else if (event.key === "Escape") setOpen(false);
          }}
          className="w-full border border-line bg-surface py-2 pr-3 pl-9 text-base text-fg placeholder:text-fg-muted focus:border-fg focus:outline-none disabled:opacity-60"
        />
      </div>
      <AnchoredList anchor={anchorRef} open={showList} id={listId} role="listbox" aria-label={`${label} results`}>
        {results.map((player, index) => (
          <li
            key={player.id}
            id={optionId(index)}
            role="option"
            aria-selected={index === active}
            // mousedown, not click: the input's blur would close the list first.
            onMouseDown={(event) => { event.preventDefault(); pick(player); }}
            onMouseEnter={() => setActive(index)}
            className={`flex cursor-pointer items-center gap-3 px-3 py-2 ${index === active ? "bg-surface" : ""}`}
          >
            <PlayerPortrait name={player.name} headshotUrl={player.headshotUrl} className="h-8 w-8" />
            <PlayerSummary player={player} />
          </li>
        ))}
      </AnchoredList>
      <p role={status === "error" ? "alert" : "status"} className={`${showList ? "mt-1 " : ""}font-mono text-[10px] tracking-[0.08em] text-fg-muted uppercase`}>
        {showList && status === "loading" ? "Searching…" : null}
        {showList && status === "error" ? error : null}
        {showList && status === "done" && results.length === 0 ? "No players found." : null}
      </p>
    </div>
  );
}

function PlayerSummary({ player, onDark = false }: { player: PlayerResult; onDark?: boolean }) {
  const statusLabel = playerStatusLabel(player.status);
  return (
    <span className="min-w-0">
      <span className={`block truncate font-slab text-base leading-tight uppercase ${onDark ? "text-white" : "text-fg"}`}>{player.name}</span>
      <span className={`block truncate font-mono text-[10px] tracking-[0.08em] uppercase ${onDark ? "text-white/75" : "text-fg-muted"}`}>
        {player.position} · {player.team}
        {statusLabel ? <span className={`ml-2 px-1.5 py-0.5 font-bold ${onDark ? "bg-black/40" : "bg-fg/10"}`}>{statusLabel}</span> : null}
      </span>
    </span>
  );
}
