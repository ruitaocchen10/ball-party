"use client";

import * as Dialog from "@radix-ui/react-dialog";
import { X } from "lucide-react";
import type { ComponentPropsWithoutRef, ReactNode, RefObject } from "react";

/**
 * The shell around a dialog: a dimmed overlay, a centered raised surface, a
 * close button, and the behavior a dialog owes its user. Escape and a click on
 * the overlay close it, focus stays inside it and returns to whatever opened
 * it, and the page behind it stops scrolling.
 *
 * Mount it while it should be open, the way the app's dialogs already work:
 * `{open ? <Modal onClose={…}>…</Modal> : null}`. The content is yours, but it
 * must contain a `ModalTitle` — that is the dialog's accessible name.
 *
 * Focus lands on the close button unless `initialFocusRef` names something
 * better, such as the first field of a form.
 */
export function Modal({
  onClose,
  closeLabel,
  size = "md",
  padded = true,
  closeButton = true,
  initialFocusRef,
  className = "",
  children,
}: {
  onClose: () => void;
  /** Accessible name of the close button, e.g. "Close feedback". */
  closeLabel: string;
  size?: "sm" | "md";
  /** Default padding around the content. Turn off when sections pad themselves. */
  padded?: boolean;
  /** Turn off when the content draws its own close control in a header bar. */
  closeButton?: boolean;
  initialFocusRef?: RefObject<HTMLElement | null>;
  className?: string;
  children: ReactNode;
}) {
  return (
    <Dialog.Root open onOpenChange={(open) => (open ? undefined : onClose())}>
      <Dialog.Portal>
        <Dialog.Overlay className="fixed inset-0 z-50 grid place-items-center overflow-y-auto bg-black/60 p-4">
          <Dialog.Content
            aria-describedby={undefined}
            onOpenAutoFocus={(event) => {
              const target = initialFocusRef?.current;
              if (!target) return;
              event.preventDefault();
              target.focus();
            }}
            className={`relative my-auto w-full ${size === "sm" ? "max-w-sm" : "max-w-md"} bg-surface-raised shadow-card outline-none ${
              padded ? "p-5" : ""
            } ${className}`.trim()}
          >
            {closeButton ? (
              <Dialog.Close
                aria-label={closeLabel}
                className="absolute top-4 right-4 flex h-9 w-9 cursor-pointer items-center justify-center text-fg-muted hover:text-fg focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-panel"
              >
                <X aria-hidden className="h-5 w-5" strokeWidth={1.5} />
              </Dialog.Close>
            ) : null}
            {children}
          </Dialog.Content>
        </Dialog.Overlay>
      </Dialog.Portal>
    </Dialog.Root>
  );
}

/** The dialog's heading, and its accessible name. Renders an `h2`; pass
 *  `asChild` to supply another element. */
export function ModalTitle(props: ComponentPropsWithoutRef<typeof Dialog.Title>) {
  return <Dialog.Title {...props} />;
}
