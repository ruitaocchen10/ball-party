"use client";

import * as RadixSelect from "@radix-ui/react-select";
import { Check, ChevronDown, ChevronUp } from "lucide-react";
import type { ReactNode } from "react";

export type SelectOption = { value: string; label: ReactNode };

const FOCUS_ON_PANEL = "focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-panel-fg";
const FOCUS_ON_DARK = "focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-hidden";

/**
 * A themed stand-in for `<select>`. The native element's trigger can be
 * styled well enough, but its open listbox is drawn by the OS, not the page —
 * on a product where every other surface is a cream panel with its own type
 * and shadow, that native popup is the one thing that can't be made to match.
 * This renders both halves itself.
 *
 * Kept name-compatible with the element it replaces: pass `name` and this
 * still lands in the enclosing form's `FormData` under that key (Radix
 * mirrors the value onto a visually hidden native `<select>` for exactly
 * that), so call sites and the server actions reading `formData.get(...)`
 * don't change.
 */
export function Select({
  name,
  ariaLabel,
  value,
  defaultValue,
  onValueChange,
  options,
  disabled,
  variant = "panel",
}: {
  name: string;
  ariaLabel: string;
  value?: string;
  defaultValue?: string;
  onValueChange?: (value: string) => void;
  options: SelectOption[];
  disabled?: boolean;
  /** `panel` for cream cards; `dark` for controls embedded in dark surfaces. */
  variant?: "panel" | "dark";
}) {
  const dark = variant === "dark";
  const focusClass = dark ? FOCUS_ON_DARK : FOCUS_ON_PANEL;
  const triggerClass = dark
    ? "border-line bg-surface text-fg"
    : "border-[#c7bfac] bg-panel-shade text-panel-fg";
  const contentClass = dark
    ? "border-line bg-surface-raised text-fg shadow-well"
    : "border-[#c7bfac] bg-panel text-panel-fg shadow-card";
  const itemClass = dark ? "data-[highlighted]:bg-surface" : "data-[highlighted]:bg-panel-shade";
  const mutedTextClass = dark ? "text-fg-muted" : "text-panel-muted";

  return (
    <RadixSelect.Root
      name={name}
      value={value}
      defaultValue={defaultValue}
      onValueChange={onValueChange}
      disabled={disabled}
    >
      <RadixSelect.Trigger
        aria-label={ariaLabel}
        className={`flex h-10 items-center justify-between gap-2 rounded border px-2 font-mono text-sm outline-none disabled:cursor-not-allowed disabled:opacity-60 ${triggerClass} ${focusClass}`}
      >
        <RadixSelect.Value />
        <RadixSelect.Icon>
          <ChevronDown className={`h-4 w-4 ${mutedTextClass}`} strokeWidth={1.75} />
        </RadixSelect.Icon>
      </RadixSelect.Trigger>

      <RadixSelect.Portal>
        <RadixSelect.Content
          position="popper"
          sideOffset={4}
          className={`z-50 w-[var(--radix-select-trigger-width)] overflow-hidden rounded border font-mono ${contentClass}`}
        >
          <RadixSelect.ScrollUpButton className={`flex h-6 items-center justify-center ${dark ? "bg-surface-raised" : "bg-panel"}`}>
            <ChevronUp className={`h-4 w-4 ${mutedTextClass}`} strokeWidth={1.75} />
          </RadixSelect.ScrollUpButton>

          <RadixSelect.Viewport
            className="max-h-[var(--radix-select-content-available-height)] p-1"
          >
            {options.map((option) => (
              <RadixSelect.Item
                key={option.value}
                value={option.value}
                className={`flex cursor-pointer items-center justify-between gap-3 px-2 py-1.5 text-sm outline-none select-none data-[disabled]:cursor-not-allowed data-[disabled]:opacity-60 ${itemClass} ${focusClass}`}
              >
                <RadixSelect.ItemText>{option.label}</RadixSelect.ItemText>
                <RadixSelect.ItemIndicator>
                  <Check className="h-3.5 w-3.5" strokeWidth={2} />
                </RadixSelect.ItemIndicator>
              </RadixSelect.Item>
            ))}
          </RadixSelect.Viewport>

          <RadixSelect.ScrollDownButton className={`flex h-6 items-center justify-center ${dark ? "bg-surface-raised" : "bg-panel"}`}>
            <ChevronDown className={`h-4 w-4 ${mutedTextClass}`} strokeWidth={1.75} />
          </RadixSelect.ScrollDownButton>
        </RadixSelect.Content>
      </RadixSelect.Portal>
    </RadixSelect.Root>
  );
}
