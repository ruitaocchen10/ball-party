"use client";

import Link from "next/link";
import { useRouter } from "next/navigation";
import { useCallback, useMemo, useRef, useState } from "react";

import { AnimatedMessage } from "@/components/foundation/ui-kit/AnimatedMessage";
import { Button, ButtonLink } from "@/components/foundation/ui-kit/Button";
import { Concealed } from "@/components/foundation/ui-kit/Concealed";
import { DashboardRail } from "@/components/foundation/ui-kit/DashboardRail";
import { PageHeader } from "@/components/foundation/ui-kit/PageHeader";
import { SlotReel } from "@/components/foundation/ui-kit/SlotReel";
import { TeamLogo } from "@/components/foundation/ui-kit/TeamLogo";
import { PlayerPortrait } from "@/components/foundation/content/prompts/PlayerPortrait";
import { FRANCHISE_NAMES, franchiseName } from "@/lib/foundation/content/nfl/franchises";
import { stableReelDecoys } from "@/lib/foundation/ui-kit/reel";
import { useTimedReveal } from "@/lib/foundation/ui-kit/useTimedReveal";
import {
  QUALITIES,
  SLOTS,
  SLOT_LABELS,
  boardFromRow,
  pickForSlot,
  type Board,
  type Slot,
  type Spin,
} from "@/lib/games/qb-season-builder/board";
import { qbErrorMessage } from "@/lib/games/qb-season-builder/messages";
import { createClient } from "@/lib/supabase/client";

/** What the player has picked out on the spin but not yet locked in. */
type Choice = { slot: Slot; playerId: string | null };

type Move = "pick" | "respin";

/** Long enough to read the reel, short enough not to interrupt each pick. */
const SPIN_REVEAL_MS = 2_000;

/**
 * The pick screen of a QB Season Builder run: this round's spin, what it
 * offers, and the six slots being filled.
 *
 * The server deals the spin, owns which slots are filled and decides whether a
 * number is shown at all — a hidden run's options arrive with their values
 * null, so the concealed marks below are an honest rendering of an absent
 * value rather than a screen that knows something it is choosing not to say.
 * Nothing here is a rule; `pick` and `respin` refuse anything this screen
 * would let through. See docs/games/qb_season_builder.md.
 *
 * Working title only — the game's name and visual design are not final.
 */
export function QbSeasonBuilderMatch({
  matchId,
  initial,
  isGuest,
}: {
  matchId: string;
  initial: Board;
  isGuest: boolean;
}) {
  const router = useRouter();
  const clientRef = useRef<ReturnType<typeof createClient> | null>(null);
  const getClient = useCallback(() => (clientRef.current ??= createClient()), []);
  const [board, setBoard] = useState<Board>(initial);
  const [choice, setChoice] = useState<Choice | null>(null);
  const [pending, setPending] = useState(false);
  const [error, setError] = useState<string | null>(null);

  /**
   * Every move is one call that answers with the whole new board — the next
   * round's spin included, dealt in the same transaction — so a screen never
   * has to guess what the server did.
   */
  async function play(move: Move) {
    if (pending) return;
    if (move === "pick" && !choice) return;
    setPending(true);
    setError(null);

    const game = getClient().schema("qb_season_builder");
    try {
      const { data, error: rpcError } = choice && move === "pick"
        ? await game.rpc("pick", {
          p_match_id: matchId,
          p_slot: choice.slot,
          ...(choice.playerId ? { p_player_id: choice.playerId } : {}),
        })
        : await game.rpc("respin", { p_match_id: matchId });

      if (rpcError) {
        setError(qbErrorMessage(rpcError.message));
        // A refusal usually means this screen is behind the server — another
        // tab moved, say — so read the run again rather than leave it stale.
        // Controls stay off until that read is back, so a second click cannot
        // race it.
        const { data: latest } = await game.rpc("state", { p_match_id: matchId });
        const current = boardFromRow(latest);
        if (current) {
          setBoard(current);
          setChoice(null);
        }
        return;
      }

      const next = boardFromRow(data);
      if (!next) {
        setError("Couldn't read this run. Reload to pick up where you left off.");
        return;
      }
      setBoard(next);
      setChoice(null);
    } finally {
      setPending(false);
    }
  }

  /**
   * Turns the six picks into the season and saves it. The page is rendered on
   * the server from the run, and a complete run renders as the staged reveal,
   * so moving on is a refresh — the same read a reload does.
   */
  async function finish() {
    if (pending) return;
    setPending(true);
    setError(null);

    const { error: rpcError } = await getClient().schema("qb_season_builder").rpc("finish", { p_match_id: matchId });

    // A run that is no longer playing is already finished — from another tab,
    // or an earlier click whose answer was lost — and its reveal is the right
    // place to land, not an error.
    if (rpcError && rpcError.message !== "match_not_playing") {
      setError(qbErrorMessage(rpcError.message));
      setPending(false);
      return;
    }
    router.refresh();
  }

  return (
    <main className="app-page flex-1">
      <div className="grid w-full gap-10 xl:grid-cols-[minmax(0,1fr)_18rem] xl:items-start xl:gap-12">
        <div className="mx-auto w-full max-w-[1080px] xl:mx-0">
          <PageHeader
            eyebrow="Solo challenge"
            title="QB Season Builder"
            description={`Round ${board.currentRound} of ${board.roundCount} · Ratings ${board.mode}`}
          />
          {board.spin === null ? (
            <div className="mt-5 grid gap-4 lg:grid-cols-[minmax(0,1fr)_18rem] lg:items-start">
              <FinishedPanel board={board} pending={pending} error={error} onFinish={finish} />
              <BuildCard board={board} isGuest={isGuest} />
            </div>
          ) : (
            <SpinPanel
              board={board}
              spin={board.spin}
              choice={choice}
              pending={pending}
              error={error}
              isGuest={isGuest}
              onChoose={setChoice}
              onPlay={play}
            />
          )}
        </div>
        <RunControlRail board={board} pending={pending} onRespin={() => play("respin")} />
      </div>
    </main>
  );
}

function SpinPanel({
  board,
  spin,
  choice,
  pending,
  error,
  isGuest,
  onChoose,
  onPlay,
}: {
  board: Board;
  spin: Spin;
  choice: Choice | null;
  pending: boolean;
  error: string | null;
  isGuest: boolean;
  onChoose: (choice: Choice) => void;
  onPlay: (move: Move) => void;
}) {
  // Who the chosen thing comes from: a quarterback, or the team for its cast.
  const chosenFrom = choice?.playerId
    ? spin.quarterbacks.find((quarterback) => quarterback.playerId === choice.playerId)?.displayName
    : franchiseName(spin.franchiseCode);
  const taken = (slot: Slot) => pickForSlot(board, slot) !== null;
  const spinKey = `${board.currentRound}-${spin.franchiseCode}-${spin.season}-${board.respinUsed}`;
  // Entering a QB run is the first deal, unlike a viewer reconnecting to a
  // live multiplayer turn, so its initial team-year deserves the same reel.
  const { revealed } = useTimedReveal(spinKey, SPIN_REVEAL_MS, false);
  const reelItems = useMemo(() => {
    const decoys = stableReelDecoys(
      Object.entries(FRANCHISE_NAMES).filter(([code]) => code !== spin.franchiseCode),
      spinKey,
      7,
    );
    return [...decoys, [spin.franchiseCode, franchiseName(spin.franchiseCode)] as [string, string]];
  }, [spin.franchiseCode, spinKey]);

  return (
    <section aria-label="The spin" className="mt-5 flex w-full max-w-[760px] flex-col gap-4">
      {revealed ? (
        <div className="flex items-center gap-3 border border-line bg-surface-raised p-4">
          <TeamSpinIdentity code={spin.franchiseCode} name={franchiseName(spin.franchiseCode)} season={spin.season} />
        </div>
      ) : (
        <div className="border border-line bg-surface-raised p-4">
          <SlotReel
            items={reelItems}
            durationMs={SPIN_REVEAL_MS}
            reelKey={spinKey}
            viewportClassName="h-12"
            rowClassName="h-12 items-center gap-3"
            itemKey={([code], index) => `${code}-${index}`}
            renderItem={([code, name]) => (
              <TeamSpinIdentity code={code} name={name} season={spin.season} />
            )}
          />
        </div>
      )}

      {revealed ? (
        <>
          <div className="grid gap-4 lg:grid-cols-2 lg:items-start">
            <div className="flex flex-col gap-4">
              {spin.quarterbacks.map((quarterback) => (
              <fieldset key={quarterback.playerId} className="border border-line bg-surface-raised p-4">
                <legend className="flex items-center gap-2 px-1 font-slab text-xl uppercase">
                  <span aria-hidden="true">
                    <PlayerPortrait name={quarterback.displayName} headshotUrl={quarterback.headshotUrl} className="h-9 w-9 text-[11px]" />
                  </span>
                  {quarterback.displayName}
                </legend>
                <div className="flex flex-col gap-1.5">
                  {QUALITIES.map((quality) => (
                    <OptionRow
                      key={quality}
                      label={SLOT_LABELS[quality]}
                      rating={quarterback.values?.[quality] ?? null}
                      disabled={taken(quality) || pending}
                      checked={choice?.slot === quality && choice.playerId === quarterback.playerId}
                      onChoose={() => onChoose({ slot: quality, playerId: quarterback.playerId })}
                    />
                  ))}
                </div>
                <div className="mt-4 border-t border-line pt-4">
                  <OptionRow
                    label={SLOT_LABELS.supporting_cast}
                    rating={spin.supportingCast}
                    name={`supporting-cast-${quarterback.playerId}`}
                    disabled={taken("supporting_cast") || pending}
                    checked={choice?.slot === "supporting_cast"}
                    onChoose={() => onChoose({ slot: "supporting_cast", playerId: null })}
                  />
                </div>
              </fieldset>
              ))}
            </div>
            <BuildCard board={board} isGuest={isGuest} />
          </div>

          <div className="flex flex-wrap items-center justify-between gap-3 border-t border-line pt-4">
            <p role="status" className="min-h-5 text-sm leading-5 text-fg-muted">
              {choice ? `Taking ${SLOT_LABELS[choice.slot]} from ${chosenFrom}` : "Choose one thing from this spin."}
            </p>
            <div className="flex gap-2">
              <Button type="button" fullWidth={false} disabled={!choice || pending} onClick={() => onPlay("pick")}>
                Lock in pick
              </Button>
            </div>
          </div>
        </>
      ) : (
        <p role="status" className="text-sm text-fg-muted">Finding this team&apos;s quarterback options…</p>
      )}
      <AnimatedMessage role="alert" className="text-sm text-hidden-text">
        {error}
      </AnimatedMessage>
    </section>
  );
}

/** One reel row and the landed state deliberately share this exact layout. */
function TeamSpinIdentity({ code, name, season }: { code: string; name: string; season: number }) {
  return (
    <>
      <TeamLogo code={code} className="h-12 w-12" />
      <div>
        <p className="font-slab text-[27px] leading-none uppercase">{name}</p>
        <p className="mt-1 font-mono text-[11px] tracking-[0.15em] text-fg-muted uppercase">{season}</p>
      </div>
    </>
  );
}

/** One thing a spin offers. A native radio so the group behaves as one choice. */
function OptionRow({
  label,
  rating,
  name = "option",
  disabled,
  checked,
  onChoose,
}: {
  label: string;
  rating: number | null;
  name?: string;
  disabled: boolean;
  checked: boolean;
  onChoose: () => void;
}) {
  return (
    <label className="flex items-center justify-between gap-3 border border-line px-2.5 py-2">
      <span className="flex items-center gap-2">
        <input type="radio" name={name} checked={checked} disabled={disabled} onChange={onChoose} />
        <span className="font-mono text-[11px] font-bold tracking-[0.1em] uppercase">{label}</span>
      </span>
      {rating === null ? (
        <Concealed label="Rating hidden" className="h-4 w-9" />
      ) : (
        <span className="font-slab text-xl leading-none tabular-nums">{rating}</span>
      )}
    </label>
  );
}

/** No round is open: all six slots are filled, so there is nothing left to pick. */
function FinishedPanel({
  board,
  pending,
  error,
  onFinish,
}: {
  board: Board;
  pending: boolean;
  error: string | null;
  onFinish: () => void;
}) {
  return (
    <section aria-label="Your quarterback" className="mt-5 flex w-full max-w-[760px] flex-col gap-3 border border-line bg-surface-raised p-4">
      <p className="font-slab text-[27px] leading-none uppercase">
        {board.phase === "complete" ? "This run is finished." : "All six slots are filled."}
      </p>
      {board.phase === "ready_to_finish" ? (
        <>
          <div>
            <Button type="button" fullWidth={false} disabled={pending} onClick={onFinish}>
              {pending ? "Revealing…" : "Reveal my season"}
            </Button>
          </div>
          <AnimatedMessage role="alert" className="text-sm text-hidden-text">
            {error}
          </AnimatedMessage>
        </>
      ) : null}
      <Link
        href="/solo"
        className="text-sm text-fg-muted underline decoration-line underline-offset-4 transition-colors hover:text-fg hover:decoration-fg"
      >
        Back to solo games
      </Link>
    </section>
  );
}

function BuildCard({ board, isGuest }: { board: Board; isGuest: boolean }) {
  return (
    <section aria-labelledby="qb-build-heading" className="border border-line bg-surface-raised p-4 shadow-well">
      <p className="font-mono text-[10px] font-semibold tracking-[0.15em] text-hidden-text uppercase">Your quarterback</p>
      <h2 id="qb-build-heading" className="mt-1 font-slab text-[27px] leading-none uppercase">Your build</h2>
      <ol aria-label="Your build" className="mt-4 divide-y divide-line border-t border-line">
        {SLOTS.map((slot) => (
          <SlotRow key={slot} slot={slot} board={board} />
        ))}
      </ol>
      {isGuest ? (
        <p className="mt-4 border-t border-line pt-3 text-[13px] leading-5 text-fg-muted">
          Playing as a guest.{" "}
          <Link href="/settings" className="text-fg underline decoration-line underline-offset-4 hover:decoration-fg">
            Create an account
          </Link>{" "}
          to keep your runs.
        </p>
      ) : null}
    </section>
  );
}

function RunControlRail({ board, pending, onRespin }: { board: Board; pending: boolean; onRespin: () => void }) {
  const [confirmingNewSeason, setConfirmingNewSeason] = useState(false);

  return (
    <DashboardRail headingId="qb-run-control-heading" eyebrow="Run control" title="Current run">
      <p className="mt-4 font-mono text-[10px] tracking-[0.13em] text-fg-muted uppercase">{board.currentRound} / {board.roundCount} rounds · mode: {board.mode}</p>
      {board.spin !== null ? (
        <div className="mt-4 border-t border-line pt-3">
          <Button type="button" variant="ghost" disabled={board.respinUsed || pending} onClick={onRespin}>
            {board.respinUsed ? "Respin used" : "Respin team"}
          </Button>
          <p className="mt-2 text-[12px] leading-4 text-fg-muted">One reroll per season.</p>
        </div>
      ) : null}
      <div className="mt-4 border-t border-line pt-3">
        {confirmingNewSeason ? (
          <div className="flex flex-col gap-2">
            <p className="text-[12px] leading-4 text-fg-muted">Leave this run and choose a new season?</p>
            <ButtonLink href="/solo" variant="ghost">Choose new season</ButtonLink>
            <Button type="button" variant="ghost" onClick={() => setConfirmingNewSeason(false)}>Keep this run</Button>
          </div>
        ) : (
          <Button type="button" variant="ghost" onClick={() => setConfirmingNewSeason(true)}>New season</Button>
        )}
      </div>
    </DashboardRail>
  );
}

function SlotRow({ slot, board }: { slot: Slot; board: Board }) {
  const pick = pickForSlot(board, slot);

  return (
    <li className="flex items-baseline justify-between gap-3 py-2.5">
      <span className="font-mono text-[10px] font-bold tracking-[0.13em] uppercase">{SLOT_LABELS[slot]}</span>
      {pick ? (
        <span className="flex items-start gap-2">
          {pick.displayName ? <PlayerPortrait name={pick.displayName} headshotUrl={pick.headshotUrl} className="h-7 w-7 text-[8px]" /> : null}
          <span className="flex flex-col items-end text-right text-[13px] leading-4">
            <span>{pick.displayName ?? franchiseName(pick.franchiseCode)}</span>
            <span className="font-mono text-[10px] text-fg-muted">
              {pick.displayName ? `${pick.season} ${franchiseName(pick.franchiseCode)}` : pick.season}
            </span>
            {pick.value !== null ? <span className="font-slab text-lg tabular-nums">{pick.value}</span> : null}
          </span>
        </span>
      ) : (
        <span className="font-mono text-[10px] tracking-[0.13em] text-fg-muted uppercase">Open</span>
      )}
    </li>
  );
}
