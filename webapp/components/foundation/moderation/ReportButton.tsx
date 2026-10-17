"use client";

import { Flag } from "lucide-react";
import { useState } from "react";

import { ReportDialog } from "@/components/foundation/moderation/ReportDialog";
import { Button } from "@/components/foundation/ui-kit/Button";
import type { ReportTarget } from "@/lib/foundation/moderation/reports";

/** The flag on a take or reply. Reporting hides it from the reporter, so the page is refreshed afterwards. */
export function ReportTakeButton({ takeId, authorName }: { takeId: string; authorName: string }) {
  const [open, setOpen] = useState(false);
  return (
    <>
      <button
        type="button"
        onClick={() => setOpen(true)}
        aria-label={`Report ${authorName}'s take`}
        className="inline-flex items-center text-fg-muted transition-colors hover:text-fg"
      >
        <Flag className="h-4 w-4" strokeWidth={1.8} />
      </button>
      {open ? (
        <ReportDialog
          target={{ kind: "take", takeId }}
          subject="this take"
          onClose={() => setOpen(false)}
          refreshOnSent
        />
      ) : null}
    </>
  );
}

/** Report beside the friend actions on another player's profile. */
export function ReportProfileButton({ profileId, displayName }: { profileId: string; displayName: string }) {
  const [open, setOpen] = useState(false);
  const target: ReportTarget = { kind: "profile", profileId };
  return (
    <>
      <Button variant="text" size="sm" fullWidth={false} onClick={() => setOpen(true)} aria-label={`Report ${displayName}`}>
        Report
      </Button>
      {open ? <ReportDialog target={target} subject={`${displayName}'s profile`} onClose={() => setOpen(false)} /> : null}
    </>
  );
}
