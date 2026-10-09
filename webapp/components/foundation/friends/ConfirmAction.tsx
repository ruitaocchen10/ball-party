"use client";

import { useState } from "react";

import { Button } from "@/components/foundation/ui-kit/Button";

/**
 * A destructive action behind one confirm step, kept subordinate: the resting
 * state is a quiet text button, and only after a click does the red `danger`
 * button appear, with Cancel beside it as the safe choice.
 */
export function ConfirmAction({
  label,
  confirmLabel,
  ariaLabel,
  disabled = false,
  onConfirm,
}: {
  label: string;
  confirmLabel: string;
  ariaLabel: string;
  disabled?: boolean;
  onConfirm: () => void;
}) {
  const [confirming, setConfirming] = useState(false);

  if (!confirming) {
    return (
      <Button variant="text" size="sm" fullWidth={false} disabled={disabled} aria-label={ariaLabel} onClick={() => setConfirming(true)}>
        {label}
      </Button>
    );
  }

  return (
    <>
      <Button variant="text" size="sm" fullWidth={false} onClick={() => setConfirming(false)}>
        Cancel
      </Button>
      <Button
        variant="danger"
        size="sm"
        fullWidth={false}
        disabled={disabled}
        aria-label={`Confirm: ${ariaLabel}`}
        onClick={() => {
          setConfirming(false);
          onConfirm();
        }}
      >
        {confirmLabel}
      </Button>
    </>
  );
}
