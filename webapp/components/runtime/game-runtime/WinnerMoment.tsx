"use client";

import { AnimatePresence, motion } from "motion/react";
import { useEffect, useState, type ReactNode } from "react";

import { GeneratedAvatar } from "@/components/foundation/identity/GeneratedAvatar";
import { EASE_OUT } from "@/lib/foundation/ui-kit/motion";

/** What the full-screen winner beat says: who won, and one line of why. */
export type WinnerMomentData = {
  faces: { name: string; avatarUrl: string | null }[];
  headline: string;
  detail?: string | null;
  /** False for a co-op loss: no rings and a muted headline, so the moment still lands without celebrating. */
  celebratory?: boolean;
};

const HOLD_MS = 2800;

/**
 * A full-screen beat over a finished match, before the results. It plays only
 * for someone who watched the match end: a player who opens or rejoins a
 * finished match goes straight to the results. Auto-advances, or click / any key
 * to skip. Same behavior as the iOS `winnerMoment` modifier.
 *
 * Call it from the match component, above any early return, and render the
 * returned node alongside the final screen. `moment` may arrive a beat after
 * `complete` (the recorded result can land late); the beat waits for it.
 */
export function useWinnerMoment(complete: boolean, moment: WinnerMomentData | null): ReactNode {
  // Fixed at mount: a match that is already over when the screen opens is never replayed.
  const [sawLive] = useState(!complete);
  const [dismissed, setDismissed] = useState(false);
  const showing = sawLive && complete && !!moment && !dismissed;

  useEffect(() => {
    if (!showing) return;
    const timer = setTimeout(() => setDismissed(true), HOLD_MS);
    return () => clearTimeout(timer);
  }, [showing]);

  return (
    <AnimatePresence>
      {showing && moment ? <WinnerMomentView key="winner-moment" moment={moment} onSkip={() => setDismissed(true)} /> : null}
    </AnimatePresence>
  );
}

function WinnerMomentView({ moment, onSkip }: { moment: WinnerMomentData; onSkip: () => void }) {
  const celebratory = moment.celebratory !== false;
  const size = moment.faces.length > 1 ? 92 : 124;
  const label = [moment.headline, moment.detail].filter(Boolean).join(". ");

  useEffect(() => {
    const skip = () => onSkip();
    window.addEventListener("keydown", skip);
    return () => window.removeEventListener("keydown", skip);
  }, [onSkip]);

  return (
    <motion.div
      role="alert"
      aria-label={label}
      onClick={onSkip}
      initial={{ opacity: 0 }}
      animate={{ opacity: 1 }}
      exit={{ opacity: 0 }}
      transition={{ duration: 0.25, ease: EASE_OUT }}
      className="fixed inset-0 z-50 flex cursor-pointer flex-col items-center justify-center gap-7 bg-surface px-5"
      style={{ backgroundImage: `radial-gradient(circle at 50% 42%, rgba(232,227,214,${celebratory ? 0.1 : 0.04}), transparent 62%)` }}
    >
      <motion.div
        aria-hidden="true"
        initial={{ scale: 0.72, opacity: 0.55 }}
        animate={{ scale: 1, opacity: celebratory ? 1 : 0.6 }}
        transition={{ type: "spring", duration: 0.6, bounce: 0.25 }}
        className="relative flex items-center justify-center"
      >
        {celebratory && (
          <>
            <span className="absolute -inset-7 rounded-full border border-fg/20" />
            <span className="absolute -inset-3.5 rounded-full border border-fg/35" />
          </>
        )}
        <span className={`flex rounded-full p-1 ${celebratory ? "border-2 border-fg" : ""}`}>
          {moment.faces.map((face, index) => (
            <span key={index} className={`flex overflow-hidden rounded-full ${index > 0 ? "-ml-2.5" : ""}`} style={{ width: size, height: size }}>
              <Face name={face.name} avatarUrl={face.avatarUrl} size={size} />
            </span>
          ))}
        </span>
      </motion.div>
      <motion.div
        initial={{ opacity: 0, y: 14 }}
        animate={{ opacity: 1, y: 0 }}
        transition={{ duration: 0.4, ease: EASE_OUT, delay: 0.1 }}
        className="flex flex-col items-center gap-2 text-center"
      >
        <p className="type-label-lg text-fg-muted">{celebratory ? "Winner" : "Final"}</p>
        <h1 className={`font-slab text-5xl uppercase leading-none sm:text-6xl ${celebratory ? "text-fg" : "text-fg-muted"}`}>{moment.headline}</h1>
        {moment.detail && <p className="type-label text-fg-muted">{moment.detail}</p>}
      </motion.div>
      <p className="absolute bottom-10 type-label text-fg-muted">Click to skip</p>
    </motion.div>
  );
}

function Face({ name, avatarUrl, size }: { name: string; avatarUrl: string | null; size: number }) {
  const [failed, setFailed] = useState(false);
  if (avatarUrl && !failed) {
    // eslint-disable-next-line @next/next/no-img-element
    return <img src={avatarUrl} alt="" onError={() => setFailed(true)} className="h-full w-full object-cover" />;
  }
  return <GeneratedAvatar name={name} size={size} className="h-full w-full" />;
}
