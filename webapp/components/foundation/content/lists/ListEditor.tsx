"use client";

import { useMemo, useRef, useState } from "react";
import { useRouter } from "next/navigation";

import { PlayerPicker } from "@/components/foundation/content/prompts/PlayerPicker";
import { Button, ButtonLink } from "@/components/foundation/ui-kit/Button";
import { Textarea } from "@/components/foundation/ui-kit/Input";
import { Modal, ModalTitle } from "@/components/foundation/ui-kit/Modal";
import { searchPlayers, type PlayerResult, type PlayerSearch } from "@/lib/foundation/content/prompts/players";
import { benchTeams, listTeamName, movedCount, moveItem, placeChange, resizeTeams, sizeLabel } from "@/lib/foundation/lists/lists";
import { saveErrorMessage } from "@/lib/foundation/lists/messages";
import type { ListKind, ListPlayer } from "@/lib/foundation/lists/types";
import { createClient } from "@/lib/supabase/client";
import { ListItemFace, PlaceChange } from "./ListRows";

const NOTE_LIMIT = 280;

/**
 * Where a player builds a list. Moving is pick up, then place: tap a row to
 * pick it up, tap another row to put it there, or use the buttons. Nothing is
 * saved until Save, and the database decides whether a save is allowed (the
 * daily limit, a prompt that is open), so this only shows what it says.
 *
 * Position lists start empty and fill by searching the player directory;
 * team lists start from all 32 teams in the saved order.
 */
export function ListEditor({
  kind,
  saved,
  players: knownPlayers,
  openPromptId,
}: {
  kind: ListKind;
  /** The newest saved version's items, or empty when the player has not started this list. */
  saved: string[];
  players: Record<string, ListPlayer>;
  /** The open prompt that feeds this list. While it is open the list is edited there. */
  openPromptId: string | null;
}) {
  const router = useRouter();
  const clientRef = useRef<ReturnType<typeof createClient> | null>(null);
  const isTeams = kind.itemKind === "team";
  const readOnly = Boolean(openPromptId);

  const [baseline, setBaseline] = useState(saved);
  const [size, setSize] = useState(() => kind.sizes.find((candidate) => candidate === saved.length) ?? kind.sizes[kind.sizes.length - 1]);
  const [items, setItems] = useState<string[]>(() => (isTeams && saved.length === 0 ? resizeTeams([], kind.sizes[kind.sizes.length - 1]) : saved));
  const [players, setPlayers] = useState(knownPlayers);
  const [selected, setSelected] = useState<string | null>(null);
  const [status, setStatus] = useState("");
  const [dialog, setDialog] = useState(false);
  const [note, setNote] = useState("");
  const [share, setShare] = useState(true);
  const [pending, setPending] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const noteRef = useRef<HTMLTextAreaElement>(null);

  const nameOf = (item: string) => (isTeams ? listTeamName(item) : (players[item]?.name ?? "Player"));
  const bench = isTeams && items.length < 32 ? benchTeams(items) : [];
  const dirty = items.length !== baseline.length || movedCount(baseline, items) > 0;
  const complete = items.length === size;
  const moves = baseline.length ? movedCount(baseline, items) : items.length;
  const selectedIndex = selected ? items.indexOf(selected) : -1;

  function place(item: string, to: number) {
    const from = items.indexOf(item);
    if (from < 0) return;
    setItems(moveItem(items, from, to));
    setStatus(`${item} is now number ${to + 1}.`);
  }

  function onRow(item: string, index: number) {
    if (readOnly) return;
    if (!selected) return setSelected(item);
    if (selected === item) return setSelected(null);
    if (items.includes(selected)) return place(selected, index);
    // A team from the bench takes this spot; whoever falls off the end goes to the bench.
    const next = [...items.slice(0, index), selected, ...items.slice(index)].slice(0, size);
    setItems(next);
    setStatus(`${selected} is now number ${index + 1}.`);
  }

  function changeSize(next: number) {
    setSize(next);
    setItems(resizeTeams(items, next));
    setSelected(null);
  }

  const search = useMemo<PlayerSearch>(() => {
    const supabase = (clientRef.current ??= createClient());
    return async (query) => {
      const outcome = await searchPlayers(supabase, query, 25);
      const position = kind.id.toUpperCase();
      return { ...outcome, players: outcome.players.filter((player) => player.position === position && !items.includes(player.id)) };
    };
  }, [kind.id, items]);

  function addPlayer(player: PlayerResult | null) {
    if (!player || items.includes(player.id) || items.length >= size) return;
    setPlayers((current) => ({ ...current, [player.id]: { id: player.id, name: player.name, position: player.position, team: player.team, headshotUrl: player.headshotUrl } }));
    setItems([...items, player.id]);
    setStatus(`${player.name} added at number ${items.length + 1}.`);
  }

  function removeItem(item: string) {
    setItems(items.filter((candidate) => candidate !== item));
    if (selected === item) setSelected(null);
  }

  async function save() {
    if (pending) return;
    setPending(true);
    setError(null);
    const { error: failure } = await (clientRef.current ??= createClient()).rpc("save_ranking_list", {
      p_kind: kind.id,
      p_items: items,
      ...(note.trim() ? { p_note: note.trim() } : {}),
      p_publish: share,
    });
    setPending(false);
    if (failure) {
      setError(saveErrorMessage(failure.message, failure.details));
      return;
    }
    setBaseline(items);
    setDialog(false);
    setNote("");
    setSelected(null);
    setStatus(share ? "Saved and shared with your friends." : "Saved.");
    router.refresh();
  }

  return (
    <section aria-label={`Edit ${kind.label}`} className="mt-5">
      {readOnly ? (
        <div className="mb-4 rounded-card bg-surface-raised p-4 shadow-well">
          <p className="text-sm leading-6 text-fg">
            This week&apos;s prompt for this list is open. Your list opens pre-filled there, and your answer saves a new version.
          </p>
          <div className="mt-3 max-w-xs">
            <ButtonLink href={`/prompts/${openPromptId}`}>Go to the prompt</ButtonLink>
          </div>
        </div>
      ) : null}

      {isTeams && kind.sizes.length > 1 ? (
        <div role="group" aria-label="List size" className="mb-4 flex gap-2">
          {kind.sizes.map((option) => (
            <button
              key={option}
              type="button"
              disabled={readOnly}
              aria-pressed={option === size}
              onClick={() => changeSize(option)}
              className={`min-h-10 rounded-full border px-4 type-label transition-colors focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-fg disabled:opacity-60 ${
                option === size ? "border-hidden bg-hidden text-fg" : "border-line text-fg-muted hover:text-fg"
              }`}
            >
              {sizeLabel(option, kind.itemKind)}
            </button>
          ))}
        </div>
      ) : null}

      <ol className="flex flex-col gap-1.5" aria-label={`${kind.label}, ${items.length} of ${size}`}>
        {items.map((item, index) => {
          const picked = selected === item;
          return (
            <li key={item} className="flex items-stretch gap-1.5">
              <button
                type="button"
                disabled={readOnly}
                aria-pressed={picked}
                aria-label={`${index + 1}, ${nameOf(item)}${picked ? ", picked up" : ""}`}
                onClick={() => onRow(item, index)}
                className={`grid min-h-14 min-w-0 flex-1 grid-cols-[2rem_minmax(0,1fr)_auto] items-center gap-3 rounded-card border px-3 py-2 text-left transition-colors focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-fg ${
                  picked
                    ? "border-hidden bg-hidden text-fg"
                    : selected
                      ? "border-dashed border-panel-line bg-panel hover:border-hidden-text"
                      : "border-panel-line bg-panel hover:bg-panel-hover"
                }`}
              >
                <span className="text-center font-slab text-2xl leading-none tabular-nums">{index + 1}</span>
                <span className={picked ? "[&_*]:!text-fg" : ""}>
                  <ListItemFace item={item} itemKind={kind.itemKind} players={players} />
                </span>
                {baseline.length ? <PlaceChange change={placeChange(baseline, items, index)} /> : <span />}
              </button>
              {!isTeams && !readOnly ? (
                <button
                  type="button"
                  onClick={() => removeItem(item)}
                  aria-label={`Remove ${players[item]?.name ?? "player"}`}
                  className="w-11 shrink-0 rounded-card border border-panel-line bg-panel type-label text-panel-muted hover:text-panel-fg focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-fg"
                >
                  <span aria-hidden>✕</span>
                </button>
              ) : null}
            </li>
          );
        })}
      </ol>

      {!isTeams && !readOnly && items.length < size ? (
        <div className="mt-4">
          <p className="type-label text-fg-muted">{items.length} of {size} · add a {kind.label.toLowerCase().replace(/s$/, "")}</p>
          <div className="mt-2">
            <PlayerPicker value={null} onChange={addPlayer} label={`Add to ${kind.label}`} search={search} />
          </div>
        </div>
      ) : null}

      {bench.length ? (
        <div className="mt-6">
          <div className="flex items-baseline justify-between">
            <h2 className="font-slab text-xl uppercase">Not ranked</h2>
            <span className="type-label text-fg-muted">{bench.length} teams</span>
          </div>
          <ul className="mt-2 flex flex-col gap-1.5">
            {bench.map((code) => {
              const picked = selected === code;
              return (
                <li key={code}>
                  <button
                    type="button"
                    disabled={readOnly}
                    aria-pressed={picked}
                    aria-label={`${nameOf(code)}, not ranked${picked ? ", picked up" : ""}`}
                    onClick={() => setSelected(picked ? null : code)}
                    className={`grid min-h-12 w-full grid-cols-[minmax(0,1fr)_auto] items-center gap-3 rounded-card border px-3 py-1.5 text-left transition-colors focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-fg ${
                      picked ? "border-hidden bg-hidden" : "border-line bg-surface hover:bg-surface-raised"
                    }`}
                  >
                    <span className={picked ? "[&_*]:!text-fg" : ""}><ListItemFace item={code} itemKind="team" players={players} /></span>
                    <span className="type-label-xs text-fg-muted">{picked ? "Picked" : "Bring in"}</span>
                  </button>
                </li>
              );
            })}
          </ul>
        </div>
      ) : null}

      <div role="status" aria-live="polite" className="sr-only">{status}</div>

      <div className="sticky bottom-0 z-10 -mx-4 mt-6 border-t border-line bg-surface px-4 pt-3 pb-4 sm:mx-0 sm:rounded-card sm:border sm:px-4">
        {selected && !readOnly ? (
          <div className="mb-3 grid gap-2">
            {selectedIndex >= 0 ? (
              <>
                <p className="text-sm text-fg-muted">
                  <span className="font-semibold text-fg">{isTeams ? selected : players[selected]?.name}</span> is number {selectedIndex + 1}. Tap a row to put them there.
                </p>
                <div className="grid grid-cols-4 gap-1.5">
                  <Button variant="ghost" size="sm" disabled={selectedIndex === 0} onClick={() => place(selected, 0)}>To #1</Button>
                  <Button variant="ghost" size="sm" disabled={selectedIndex === 0} onClick={() => place(selected, selectedIndex - 1)}>Up</Button>
                  <Button variant="ghost" size="sm" disabled={selectedIndex === items.length - 1} onClick={() => place(selected, selectedIndex + 1)}>Down</Button>
                  <Button variant="ghost" size="sm" disabled={selectedIndex === items.length - 1} onClick={() => place(selected, items.length - 1)}>To #{items.length}</Button>
                </div>
              </>
            ) : (
              <p className="text-sm text-fg-muted">
                Bringing in <span className="font-semibold text-fg">{selected}</span>. Tap a spot in your list. The last team drops to the bench.
              </p>
            )}
            <Button variant="text" size="sm" fullWidth={false} onClick={() => setSelected(null)}>Done moving</Button>
          </div>
        ) : null}
        <div className="flex items-center gap-3">
          <p className="min-w-0 flex-1 text-sm leading-5 text-fg-muted">
            {readOnly
              ? "Editing is paused until the prompt locks."
              : !complete
                ? `${items.length} of ${size} chosen. Finish the list to save it.`
                : dirty
                  ? <><span className="font-semibold text-fg">{moves} moved</span> since your saved list.</>
                  : "No changes yet."}
          </p>
          {dirty && baseline.length ? (
            <Button variant="text" fullWidth={false} onClick={() => { setItems(isTeams ? resizeTeams(baseline, baseline.length) : baseline); setSize(kind.sizes.find((candidate) => candidate === baseline.length) ?? size); setSelected(null); }}>
              Undo
            </Button>
          ) : null}
          <Button fullWidth={false} disabled={readOnly || !dirty || !complete} onClick={() => { setError(null); setDialog(true); }}>
            Save
          </Button>
        </div>
      </div>

      {dialog ? (
        <Modal onClose={() => !pending && setDialog(false)} closeLabel="Close save" initialFocusRef={noteRef}>
          <ModalTitle className="font-slab text-3xl uppercase">Save your {kind.label.toLowerCase()}</ModalTitle>
          <p className="mt-1 text-sm text-fg-muted">
            {moves} moved. It joins your history right away.
          </p>
          <label className="mt-4 block">
            <span className="type-label text-fg-muted">Why the change? (optional)</span>
            <Textarea
              ref={noteRef}
              variant="well"
              className="mt-1.5 min-h-24"
              maxLength={NOTE_LIMIT}
              value={note}
              onChange={(event) => setNote(event.target.value)}
              placeholder="Friends see this with your update."
            />
            <span className="mt-1 block text-right type-label-xs text-fg-muted">{note.length} / {NOTE_LIMIT}</span>
          </label>
          <label className="mt-3 flex cursor-pointer items-start gap-3 rounded-card border border-line bg-surface-raised p-3">
            <input type="checkbox" checked={share} onChange={(event) => setShare(event.target.checked)} className="mt-1 h-4 w-4 accent-hidden" />
            <span>
              <span className="block text-sm font-semibold text-fg">Share this update with friends</span>
              <span className="block text-xs leading-5 text-fg-muted">
                Friends only, and they can reply. Turn it off to save quietly. The version still shows in your history.
              </span>
            </span>
          </label>
          {error ? <p role="alert" className="mt-3 text-sm text-hidden-text">{error}</p> : null}
          <div className="mt-4 grid gap-2">
            <Button disabled={pending} onClick={save}>{pending ? "Saving…" : share ? "Save and share" : "Save"}</Button>
            <Button variant="text" disabled={pending} onClick={() => setDialog(false)}>Keep editing</Button>
          </div>
        </Modal>
      ) : null}
    </section>
  );
}
