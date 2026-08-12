"use client";

/**
 * A scratch harness for arguing about the auction screen without playing a
 * match. Route: /dev/auction
 *
 * This file is the CHROME ONLY. The screen itself lives in ./AuctionScreen.tsx,
 * which is the file to edit; the fixture it reads is ./fixture.ts and the states
 * are ./scenarios.ts.
 *
 * Pick a state from the strip at the top. Every state below is one a real player
 * reaches; several are awkward to get to on purpose (nobody bid, you are locked
 * out, you are broke). Scrub the clock to see the urgent treatment.
 *
 * WHY THE PHONE VIEW IS AN IFRAME. The build's breakpoints are plain Tailwind
 * `lg:`, which is a VIEWPORT media query — so shrinking a wrapper div to 402px
 * does not give you the phone layout, it gives you the desktop layout crushed
 * into 402px, which is a lie. An iframe has its own viewport, so the media
 * queries resolve against the frame. It loads ./frame, the same screen with no
 * chrome around it.
 */

import { useState } from "react";
import Link from "next/link";

import { AuctionScreen } from "./AuctionScreen";
import { SCENARIOS, type Scenario } from "./scenarios";

export default function DevAuctionPage() {
  const [id, setId] = useState(SCENARIOS[1].id);
  const [seconds, setSeconds] = useState<number | null>(SCENARIOS[1].seconds);
  const [phone, setPhone] = useState(false);
  const [stamped, setStamped] = useState(false);
  const [open, setOpen] = useState(true);
  const scenario = SCENARIOS.find((s) => s.id === id) ?? SCENARIOS[0];

  const pick = (next: Scenario) => { setId(next.id); setSeconds(next.seconds); };

  return (
    <>
      {/* The chrome FLOATS, at the BOTTOM. It floats because the auction is
          designed never to scroll, so a control strip in normal flow would
          shorten the viewport it is being judged in and quietly change the
          thing under test. It sits at the bottom because the screen's own top
          edge is now load-bearing — the board strip and the account menu live
          up there, and dev chrome parked over them hides the thing being
          looked at. Hide it to see the screen at a true viewport height. */}
      <DevBar
        scenario={scenario}
        seconds={seconds}
        phone={phone}
        open={open}
        onPick={pick}
        onSeconds={setSeconds}
        onPhone={setPhone}
        stamped={stamped}
        onStamped={setStamped}
        onOpen={setOpen}
      />

      {phone ? (
        <div className="flex h-dvh items-start justify-center bg-[#0b0b0c] pt-4 pb-16">
          {/* 402 wide is the inner width of the phone shell on the design sheet;
              the height gives way so the frame always clears the floating bar,
              which is now below it. */}
          <iframe
            title="The auction at phone width"
            src={`/dev/auction/frame?state=${scenario.id}&secs=${seconds ?? ""}${stamped ? "&stamp=1" : ""}`}
            width={402}
            className="h-[min(780px,100%)] rounded-[30px] border-0 shadow-[0_0_0_9px_#0b0b0c,0_0_0_10px_#3c3e41,0_22px_44px_rgba(0,0,0,.5)]"
          />
        </div>
      ) : (
        /* One viewport tall, which is what body.flex + main.flex-1 gives the
           screen in the real app. */
        <div className="flex h-dvh flex-col bg-surface">
          <AuctionScreen
            key={scenario.id}
            scenario={scenario}
            remainingMs={seconds === null ? null : seconds * 1000}
            stamped={stamped}
          />
        </div>
      )}
    </>
  );
}

function DevBar({
  scenario, seconds, phone, stamped, open, onPick, onSeconds, onPhone, onStamped, onOpen,
}: {
  scenario: Scenario;
  seconds: number | null;
  phone: boolean;
  stamped: boolean;
  open: boolean;
  onPick: (s: Scenario) => void;
  onSeconds: (n: number) => void;
  onPhone: (b: boolean) => void;
  onStamped: (b: boolean) => void;
  onOpen: (b: boolean) => void;
}) {
  return (
    <div className="fixed inset-x-0 bottom-0 z-50 border-t-2 border-dashed border-line bg-[#141517]/95 px-4 py-2 font-mono text-[11px] text-fg-muted backdrop-blur">
      <div className="mx-auto flex max-w-7xl flex-col gap-2.5">
        <div className="flex items-center gap-3">
          <span className="tracking-[0.14em] uppercase">Dev · auction states</span>
          <span className="truncate text-fg-muted/70">{scenario.label}</span>
          <button
            type="button"
            onClick={() => onOpen(!open)}
            className="ml-auto rounded-[3px] border border-line px-2 py-1 hover:border-fg-muted hover:text-fg"
          >
            {open ? "hide" : "show"}
          </button>
          <Link href="/" className="underline underline-offset-2 hover:text-fg">leave</Link>
        </div>

        {open ? (
          <>
            <div className="flex flex-wrap items-center gap-1.5">
              {SCENARIOS.map((s) => (
                <button
                  key={s.id}
                  type="button"
                  onClick={() => onPick(s)}
                  className={`rounded-[3px] border px-2 py-1 transition-colors ${
                    s.id === scenario.id
                      ? "border-panel bg-panel text-panel-fg"
                      : "border-line text-fg-muted hover:border-fg-muted hover:text-fg"
                  }`}
                >
                  {s.label}
                </button>
              ))}
            </div>

            <div className="flex flex-wrap items-center gap-4">
              <label className="flex items-center gap-2">
                <span className="tracking-[0.14em] uppercase">Clock</span>
                <input
                  type="range"
                  min={0}
                  max={20}
                  value={seconds ?? 0}
                  disabled={seconds === null}
                  onChange={(e) => onSeconds(Number(e.target.value))}
                  className="w-40 accent-[#e8e4dc] disabled:opacity-30"
                />
                <span className="w-8 tabular-nums">{seconds === null ? "—" : `${seconds}s`}</span>
              </label>
              <label className="flex items-center gap-2">
                <input type="checkbox" checked={phone} onChange={(e) => onPhone(e.target.checked)} />
                <span className="tracking-[0.14em] uppercase">Phone · 402 × 780</span>
              </label>
              {/* The A/B for the whole "state, not text" idea: stamps the lot
                  card when you are out of it, and drops the rail's three status
                  words in favour of the seat itself. */}
              <label className="flex items-center gap-2">
                <input type="checkbox" checked={stamped} onChange={(e) => onStamped(e.target.checked)} />
                <span className="tracking-[0.14em] uppercase">Card states, not text</span>
              </label>
            </div>

            <p className="max-w-3xl leading-relaxed text-fg-muted/80">{scenario.note}</p>
          </>
        ) : null}
      </div>
    </div>
  );
}
