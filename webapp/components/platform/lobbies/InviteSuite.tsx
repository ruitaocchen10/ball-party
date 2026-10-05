"use client";

import { useState } from "react";

const FOCUS =
  "focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-panel";

/**
 * The room's one invite surface: the code, and a one-tap way to hand someone
 * a working link instead of five characters to read out over a call.
 * /lobby/[code] already handles a cold landing — InviteAccountGate and
 * AutoJoinRoom (see app/lobby/[code]/page.tsx) are exactly what a stranger
 * following this link hits — so there is nothing new to wire up
 * server-side, only a way to hand the link over. Lives in LobbyTopStrip's
 * own empty middle rather than the old below-strip header, so inviting is
 * always in reach instead of scrolled past once the roster fills the screen.
 *
 * `navigator.share` (the OS share sheet — Messages, Mail, AirDrop, whatever
 * the device offers) is preferred where it exists, since "text this to a
 * friend" is exactly what it is for. Everywhere else falls back to copying
 * the link to the clipboard.
 */
export function InviteSuite({ code }: { code: string }) {
  const [status, setStatus] = useState<"idle" | "copied-code" | "copied-link">("idle");

  function flash(next: "copied-code" | "copied-link") {
    setStatus(next);
    setTimeout(() => setStatus("idle"), 1800);
  }

  async function copyCode() {
    try {
      await navigator.clipboard.writeText(code);
      flash("copied-code");
    } catch {
      // Clipboard blocked (no permission, insecure context) — the code is
      // already on screen to read out, so there's no fallback needed.
    }
  }

  async function invite() {
    const url = `${window.location.origin}/lobby/${code}`;
    if (typeof navigator.share === "function") {
      try {
        await navigator.share({ title: "Join my Ball Party room", text: `Join my room — code ${code}`, url });
      } catch {
        // Cancelled share sheet — not an error worth surfacing.
      }
      return;
    }
    try {
      await navigator.clipboard.writeText(url);
      flash("copied-link");
    } catch {
      // Nothing to fall back to if the clipboard itself is blocked.
    }
  }

  return (
    <div className="flex flex-col items-center gap-1.5 sm:flex-row sm:gap-3">
      <button
        type="button"
        onClick={copyCode}
        aria-label="Copy join code"
        className={`text-center transition-colors hover:text-fg-muted ${FOCUS}`}
      >
        <span className="block type-label-xs text-fg-muted">
          {status === "copied-code" ? "Copied" : "Join code"}
        </span>
        <span className="block font-mono text-lg leading-none font-semibold tracking-[0.16em] text-fg">
          {code}
        </span>
      </button>

      <button
        type="button"
        onClick={invite}
        className={`flex h-9 shrink-0 items-center justify-center bg-panel px-3.5 type-label font-bold text-panel-fg transition-colors hover:bg-panel-hover ${FOCUS}`}
      >
        {status === "copied-link" ? "Link copied" : "Invite friends"}
      </button>
    </div>
  );
}
