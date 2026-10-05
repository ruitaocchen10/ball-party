"use client";

import { Brain, Footprints, RefreshCw, Shield, Sparkles, Target, Users, Zap, type LucideIcon } from "lucide-react";
import Link from "next/link";
import { useRouter } from "next/navigation";
import { useCallback, useEffect, useMemo, useRef, useState } from "react";

import { AnimatedMessage } from "@/components/foundation/ui-kit/AnimatedMessage";
import { Button } from "@/components/foundation/ui-kit/Button";
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
  type Grade,
  type Slot,
  type Spin,
} from "@/lib/games/qb-season-builder/board";
import { GuestNudge } from "@/components/games/qb-season-builder/GuestNudge";
import { qbErrorMessage } from "@/lib/games/qb-season-builder/messages";
import { createClient } from "@/lib/supabase/client";
import { PageShell } from "@/components/foundation/ui-kit/PageShell";

/** What the player has picked out on the spin but not yet locked in. */
type Choice = { slot: Slot; playerId: string | null };

type Move = "pick" | "respin";

/** Long enough to read the reel, short enough not to interrupt each pick. */
const SPIN_REVEAL_MS = 2_000;

/** Which icon stands in for each trait row — see OptionRow. */
const SLOT_ICONS: Record<Slot, LucideIcon> = {
  accuracy: Target,
  arm_talent: Zap,
  mobility: Footprints,
  iq: Brain,
  build: Shield,
  supporting_cast: Users,
};

/**
 * The pick screen of a QB Season Builder run: this round's spin, what it
 * offers, and the six slots being filled.
 *
 * The server deals the spin, owns which slots are filled and decides whether a
 * number is shown at all — a hidden run's options arrive with their values
 * null, so the concealed marks below are an honest rendering of an absent
 * value rather than a screen that knows something it is choosing not to say.
 * Nothing here is a rule; `pick` and `respin` refuse anything this screen
 * would let through. See docs/games/qb_season_builder/rules.md.
 *
 * Working title only — the game's name and visual design are not final.
 */
export function QbSeasonBuilderMatch({
  matchId,
  initial,
  isGuest,
  startNewSeason,
}: {
  matchId: string;
  initial: Board;
  isGuest: boolean;
  /**
   * Deals a fresh solo run and redirects to it — `playSolo`
   * (`lib/platform/lobbies/actions`), handed down from the page rather than
   * imported here: a game may never import platform directly (see
   * docs/architecture/architecture.md), so the one call this screen needs
   * into it arrives as a prop instead.
   */
  startNewSeason: (formData: FormData) => void;
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

  // The last pick goes straight to the reveal — there is nothing to confirm.
  // Tried once per mount: if it fails, the panel below offers the retry rather
  // than this effect looping on the error.
  const autoFinished = useRef(false);
  useEffect(() => {
    if (board.phase !== "ready_to_finish" || autoFinished.current) return;
    autoFinished.current = true;
    void finish();
    // eslint-disable-next-line react-hooks/exhaustive-deps -- finish is re-made every render; the ref makes this fire once
  }, [board.phase]);

  return (
    <PageShell variant="dashboard">
      <div className="grid w-full gap-10 xl:grid-cols-[minmax(0,1fr)_18rem] xl:items-start xl:gap-12">
        <div className="mx-auto w-full max-w-[1080px] xl:mx-0">
          <PageHeader
            eyebrow="Solo challenge"
            title="QB Season Builder"
            description={`Round ${board.currentRound} of ${board.roundCount} · Grades ${board.mode} · Era ${board.era}`}
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
        <RunControlRail board={board} pending={pending} onRespin={() => play("respin")} startNewSeason={startNewSeason} />
      </div>
    </PageShell>
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

      <div className="grid gap-4 lg:grid-cols-2 lg:items-start">
        <div className="flex flex-col gap-4">
          {revealed ? (
            spin.quarterbacks.map((quarterback) => (
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
                      icon={SLOT_ICONS[quality]}
                      label={SLOT_LABELS[quality]}
                      grade={quarterback.grades?.[quality] ?? null}
                      taken={taken(quality)}
                      disabled={taken(quality) || pending}
                      checked={choice?.slot === quality && choice.playerId === quarterback.playerId}
                      onChoose={() => onChoose({ slot: quality, playerId: quarterback.playerId })}
                    />
                  ))}
                </div>
                <div className="mt-4 border-t border-line pt-4">
                  <OptionRow
                    icon={SLOT_ICONS.supporting_cast}
                    label={SLOT_LABELS.supporting_cast}
                    grade={spin.supportingCastGrade}
                    name={`supporting-cast-${quarterback.playerId}`}
                    taken={taken("supporting_cast")}
                    disabled={taken("supporting_cast") || pending}
                    checked={choice?.slot === "supporting_cast"}
                    onChoose={() => onChoose({ slot: "supporting_cast", playerId: null })}
                  />
                </div>
              </fieldset>
            ))
          ) : (
            <p role="status" className="text-sm text-fg-muted">Finding this team&apos;s quarterback options…</p>
          )}
        </div>
        <BuildCard board={board} isGuest={isGuest} />
      </div>

      {revealed ? (
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
      ) : null}
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
        <p className="mt-1 type-label-lg text-fg-muted">{season}</p>
      </div>
    </>
  );
}

/**
 * One thing a spin offers. A native radio (visually hidden, but still what a
 * screen reader and `taken()`'s `checked` state hang off of) inside a
 * `<label>`, so the whole row — not just the old dot — is the click target
 * and clicking anywhere on it selects the trait.
 *
 * The trait's icon stands in for the dot. At rest it's a quiet outline;
 * picking the row fills the whole thing with the same cream tone `<Button>`
 * uses for its one primary action, so "this is my pick" reads at a glance
 * against the board rather than only up close. Explored as three variants in
 * a throwaway prototype (`app/prototype/qb-trait-rows`) before this one won.
 *
 * `taken` is its own prop rather than folded into `disabled`: a slot already
 * filled from an earlier spin reads differently from one merely waiting on a
 * pending request, so it gets its own greyed-out look and its own "why" —
 * the same rule AuctionClock follows, that a disabled control always says why
 * rather than leaving "already picked" indistinguishable from "broken".
 */
function OptionRow({
  icon: Icon,
  label,
  grade,
  name = "option",
  taken = false,
  disabled,
  checked,
  onChoose,
}: {
  icon: LucideIcon;
  label: string;
  grade: Grade | null;
  name?: string;
  taken?: boolean;
  disabled: boolean;
  checked: boolean;
  onChoose: () => void;
}) {
  const active = checked && !taken;
  return (
    <label
      className={`flex items-center justify-between gap-3 border px-2.5 py-2.5 transition-colors ${
        taken
          ? "cursor-not-allowed border-line bg-surface opacity-50"
          : active
            ? "cursor-pointer border-panel bg-panel text-panel-fg"
            : "cursor-pointer border-line hover:border-fg-muted"
      }`}
    >
      <span className="flex items-center gap-2.5">
        <input type="radio" name={name} className="sr-only" checked={checked} disabled={disabled} onChange={onChoose} />
        <Icon aria-hidden className={`h-4 w-4 ${active ? "text-panel-fg" : "text-fg-muted"}`} strokeWidth={active ? 2.25 : 1.5} />
        <span className="type-label-lg font-bold">{label}</span>
      </span>
      {taken ? (
        <span className="type-label text-fg-muted">Already picked</span>
      ) : grade === null ? (
        <Concealed label="Grade hidden" compact className="h-4 w-9" />
      ) : (
        <span className="font-slab text-xl leading-none">{grade}</span>
      )}
    </label>
  );
}

/**
 * No round is open. A `ready_to_finish` run is already on its way to the
 * reveal (see the effect above), so this only shows progress — and, if that
 * call failed, the reason and a way to try again.
 */
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
      {board.phase === "complete" ? (
        <p className="font-slab text-[27px] leading-none uppercase">This run is finished.</p>
      ) : (
        <>
          <p role="status" className="font-slab text-[27px] leading-none uppercase">
            {pending || !error ? "Revealing your season…" : "Couldn't reveal your season."}
          </p>
          {error && !pending ? (
            <div>
              <Button type="button" fullWidth={false} onClick={onFinish}>
                Try again
              </Button>
            </div>
          ) : null}
          <AnimatedMessage role="alert" className="text-sm text-hidden-text">
            {error}
          </AnimatedMessage>
        </>
      )}
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
      <p className="type-label font-semibold text-hidden-text">Your quarterback</p>
      <h2 id="qb-build-heading" className="mt-1 font-slab text-[27px] leading-none uppercase">Your build</h2>
      <ol aria-label="Your build" className="mt-4 divide-y divide-line border-t border-line">
        {SLOTS.map((slot) => (
          <SlotRow key={slot} slot={slot} board={board} />
        ))}
      </ol>
      {isGuest ? (
        <GuestNudge className="mt-4 border-t border-line pt-3 text-[13px] leading-5 text-fg-muted" />
      ) : null}
    </section>
  );
}

function RunControlRail({
  board,
  pending,
  onRespin,
  startNewSeason,
}: {
  board: Board;
  pending: boolean;
  onRespin: () => void;
  startNewSeason: (formData: FormData) => void;
}) {
  return (
    <DashboardRail headingId="qb-run-control-heading" eyebrow="Run control" title="Current run">
      <p className="mt-4 type-label text-fg-muted">{board.currentRound} / {board.roundCount} rounds · mode: {board.mode} · era: {board.era}</p>
      {board.spin !== null ? (
        <div className="mt-4 border-t border-line pt-3">
          <Button className="flex items-center justify-center" type="button" variant="ghost" disabled={board.respinUsed || pending} onClick={onRespin}>
            <span className="inline-flex items-center justify-center gap-2">
              <RefreshCw aria-hidden className="h-4 w-4" />
              <span className="font-slab-optical-center">{board.respinUsed ? "Respin used" : "Respin team"}</span>
            </span>
          </Button>
          <p className="mt-2 text-[12px] leading-4 text-fg-muted">One reroll per season.</p>
        </div>
      ) : null}
      <div className="mt-4 border-t border-line pt-3">
        {/* One click, no confirmation: abandons this run and deals a fresh
         *  one immediately, in the same grades mode and era this run is
         *  playing in. */}
        <form action={startNewSeason}>
          <input type="hidden" name="game" value="qb_season_builder" />
          <input type="hidden" name="mode" value={board.mode} />
          <input type="hidden" name="era" value={board.era} />
          <Button className="flex items-center justify-center" type="submit" variant="ghost">
            <span className="inline-flex items-center justify-center gap-2">
              <Sparkles aria-hidden className="h-4 w-4" />
              <span className="font-slab-optical-center">New season</span>
            </span>
          </Button>
        </form>
        <p className="mt-2 text-[12px] leading-4 text-fg-muted">Starts over immediately — this run is left behind.</p>
      </div>
    </DashboardRail>
  );
}

function SlotRow({ slot, board }: { slot: Slot; board: Board }) {
  const pick = pickForSlot(board, slot);

  return (
    <li className="flex items-baseline justify-between gap-3 py-2.5">
      <span className="type-label font-bold">{SLOT_LABELS[slot]}</span>
      {pick ? (
        <span className="flex items-start gap-2">
          {pick.displayName ? <PlayerPortrait name={pick.displayName} headshotUrl={pick.headshotUrl} className="h-7 w-7 text-[8px]" /> : null}
          <span className="flex flex-col items-end text-right text-[13px] leading-4">
            <span>{pick.displayName ?? franchiseName(pick.franchiseCode)}</span>
            <span className="font-mono text-[10px] text-fg-muted">
              {pick.displayName ? `${pick.season} ${franchiseName(pick.franchiseCode)}` : pick.season}
            </span>
            {pick.grade !== null ? <span className="font-slab text-lg">{pick.grade}</span> : null}
          </span>
        </span>
      ) : (
        <span className="type-label text-fg-muted">Open</span>
      )}
    </li>
  );
}
