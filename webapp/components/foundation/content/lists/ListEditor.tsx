"use client";

import { useMemo, useRef, useState, type DragEvent } from "react";
import { useRouter } from "next/navigation";

import { AuthorIdentity } from "@/components/foundation/content/prompts/AuthorIdentity";
import { PlayerPicker } from "@/components/foundation/content/prompts/PlayerPicker";
import { Badge } from "@/components/foundation/ui-kit/Badge";
import { Button, ButtonLink } from "@/components/foundation/ui-kit/Button";
import { searchPlayers, type PlayerResult, type PlayerSearch } from "@/lib/foundation/content/prompts/players";
import { benchTeams, listTeamName, listTitle, movedCount, moveItem, placeChange, resizeTeams, sizeLabel } from "@/lib/foundation/lists/lists";
import { saveErrorMessage } from "@/lib/foundation/lists/messages";
import type { ListKind, ListPlayer } from "@/lib/foundation/lists/types";
import { createClient } from "@/lib/supabase/client";
import { ListTile, listGridClass } from "./ListRows";

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
  displayName,
  avatarUrl,
  username,
}: {
  kind: ListKind;
  /** The newest saved version's items, or empty when the player has not started this list. */
  saved: string[];
  players: Record<string, ListPlayer>;
  /** The open prompt that feeds this list. While it is open the list is edited there. */
  openPromptId: string | null;
  displayName: string;
  avatarUrl: string | null;
  username: string | null;
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
  const [note, setNote] = useState("");
  const [share, setShare] = useState(true);
  const [dragged, setDragged] = useState<string | null>(null);
  const [over, setOver] = useState<number | null>(null);
  const [pending, setPending] = useState(false);
  const [error, setError] = useState<string | null>(null);

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

  /** Something dragged onto a place: a ranked item moves there, a team from the bench takes the place. */
  function dropOn(dragged: string, index: number) {
    setDragged(null);
    setOver(null);
    if (readOnly) return;
    if (items.includes(dragged)) return place(dragged, index);
    if (!isTeams || !benchTeams(items).includes(dragged)) return;
    setItems([...items.slice(0, index), dragged, ...items.slice(index)].slice(0, size));
    setSelected(null);
    setStatus(`${dragged} is now number ${index + 1}.`);
  }

  /** The props that make a tile draggable by its item (a team code or a player id). */
  function dragProps(item: string) {
    if (readOnly) return {};
    return {
      draggable: true,
      onDragStart: (event: DragEvent<HTMLElement>) => {
        event.dataTransfer.setData("text/plain", item);
        event.dataTransfer.effectAllowed = "move";
        setDragged(item);
      },
      onDragEnd: () => {
        setDragged(null);
        setOver(null);
      },
    };
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
    setNote("");
    setSelected(null);
    setStatus(share ? "Saved and shared with your friends." : "Saved.");
    router.refresh();
  }

  const title = listTitle(kind, size).replace(/^My /, "");

  return (
    <section aria-label={`Edit ${kind.label}`} className="mt-5 w-full pb-16">
      {readOnly ? (
        <div className="mb-5 rounded-card bg-surface-raised p-4 shadow-well">
          <p className="text-sm leading-6 text-fg">
            This week&apos;s prompt for this list is open. Your list opens pre-filled there, and your answer saves a new version.
          </p>
          <div className="mt-3 max-w-xs">
            <ButtonLink href={`/prompts/${openPromptId}`}>Go to the prompt</ButtonLink>
          </div>
        </div>
      ) : null}

      <div className="relative overflow-hidden rounded-card border border-line bg-surface-raised text-fg shadow-[0_10px_24px_rgb(0_0_0/0.4)]">
        <div className="flex items-center gap-2.5 px-4 pt-4">
          <AuthorIdentity name={displayName} avatarUrl={avatarUrl} username={username} />
          <Badge>You</Badge>
        </div>

        <div className="px-4 pt-4">
          <label htmlFor={`list-take-${kind.id}`} className="type-label text-fg-muted">
            Add a take <span className="normal-case">(optional)</span>
          </label>
          <textarea
            id={`list-take-${kind.id}`}
            value={note}
            onChange={(event) => setNote(event.target.value)}
            maxLength={NOTE_LIMIT}
            rows={2}
            disabled={readOnly}
            placeholder="Why the change? Friends see this with your update."
            className="mt-2 block w-full resize-none rounded-card border border-line bg-surface px-3 py-2 text-lg leading-6 text-fg placeholder:text-fg-muted focus:border-fg focus:outline-none disabled:opacity-60"
          />
        </div>

        <div className="px-4 pt-4">
          <div className="flex items-center justify-between gap-3">
            <div>
              <p className="font-slab text-2xl uppercase">Your {title}</p>
              <p className="font-mono text-xs text-fg-muted">Drag a row where it goes, or tap one to pick it up and tap its new spot.</p>
            </div>
            {isTeams && kind.sizes.length > 1 ? (
              <div role="group" aria-label="List size" className="flex shrink-0 gap-1">
                {kind.sizes.map((option) => (
                  <button
                    key={option}
                    type="button"
                    disabled={readOnly}
                    aria-pressed={option === size}
                    onClick={() => changeSize(option)}
                    className={`rounded-card px-2.5 py-2 font-mono text-[10px] uppercase disabled:cursor-default ${option === size ? "bg-hidden text-fg" : "border border-line bg-surface text-fg-muted"}`}
                  >
                    {sizeLabel(option, kind.itemKind)}
                  </button>
                ))}
              </div>
            ) : null}
          </div>

          <ol className={`mt-4 ${listGridClass(size)}`} aria-label={`${kind.label}, ${items.length} of ${size}`}>
            {items.map((item, index) => (
              <li
                key={item}
                {...dragProps(item)}
                onDragOver={(event) => {
                  if (readOnly || !dragged) return;
                  event.preventDefault();
                  setOver(index);
                }}
                onDrop={(event) => {
                  event.preventDefault();
                  dropOn(event.dataTransfer.getData("text/plain") || (dragged ?? ""), index);
                }}
                className={`relative min-w-0 rounded-card ${dragged === item ? "opacity-40" : ""} ${over === index && dragged !== item ? "outline-2 outline-fg" : ""}`}
              >
                <ListTile
                  item={item}
                  itemKind={kind.itemKind}
                  players={players}
                  rank={index + 1}
                  change={baseline.length ? placeChange(baseline, items, index) : undefined}
                  picked={selected === item}
                  disabled={readOnly}
                  onClick={() => onRow(item, index)}
                  ariaLabel={`${index + 1}, ${nameOf(item)}${selected === item ? ", picked up" : ""}`}
                  trailing={!isTeams && !readOnly ? <span aria-hidden className="type-label text-surface">✕</span> : undefined}
                />
                {!isTeams && !readOnly ? (
                  <button
                    type="button"
                    onClick={() => removeItem(item)}
                    aria-label={`Remove ${players[item]?.name ?? "player"}`}
                    className="absolute inset-y-0 right-0 w-9 focus-visible:outline-2 focus-visible:-outline-offset-2 focus-visible:outline-fg"
                  />
                ) : null}
              </li>
            ))}
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
            <div className="mt-5">
              <p className="mb-1.5 type-label text-fg-muted">Not ranked · {bench.length} teams</p>
              <ul className="grid grid-cols-2 gap-1.5 sm:grid-cols-4">
                {bench.map((code) => (
                  <li key={code} {...dragProps(code)} className={`min-w-0 ${dragged === code ? "opacity-40" : ""}`}>
                    <ListTile
                      item={code}
                      itemKind="team"
                      players={players}
                      rank={null}
                      picked={selected === code}
                      disabled={readOnly}
                      onClick={() => setSelected(selected === code ? null : code)}
                      ariaLabel={`${nameOf(code)}, not ranked${selected === code ? ", picked up" : ""}`}
                    />
                  </li>
                ))}
              </ul>
            </div>
          ) : null}
        </div>

        {selected && !readOnly ? (
          <div className="mx-4 mt-4 grid gap-2 rounded-card border border-line bg-surface p-3">
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

        <div role="status" aria-live="polite" className="sr-only">{status}</div>

        <div className="mt-5 px-4 pb-4">
          <label className="flex cursor-pointer items-start gap-3">
            <input type="checkbox" checked={share} disabled={readOnly} onChange={(event) => setShare(event.target.checked)} className="mt-1 h-4 w-4 accent-hidden" />
            <span>
              <span className="block text-sm font-semibold text-fg">Share this update with friends</span>
              <span className="block text-xs leading-5 text-fg-muted">Friends only, and they can reply. Turn it off to save quietly; the version still shows in your history.</span>
            </span>
          </label>
          <div className="mt-4 flex items-center gap-3">
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
          </div>
          <div className="mt-3">
            <Button variant="solid" fullWidth disabled={readOnly || !dirty || !complete || pending} onClick={save}>
              {pending ? "Saving…" : share ? "Save and share" : "Save"}
            </Button>
          </div>
          {error ? <p role="alert" className="mt-3 text-sm text-hidden-text">{error}</p> : null}
        </div>
      </div>
    </section>
  );
}
