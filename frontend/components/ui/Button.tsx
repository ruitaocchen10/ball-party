import type { ButtonHTMLAttributes } from "react";

/**
 * Buttons are cream, because a button is a known thing and everything known in
 * this product is card stock. `ghost` is for the subordinate action on a screen
 * — one primary per view.
 *
 * Focus rings are cream rather than red: red is reserved for hidden state, and
 * a focus ring is the opposite of hidden.
 */
type Props = ButtonHTMLAttributes<HTMLButtonElement> & {
  variant?: "solid" | "ghost";
  /** Full width is the common case; turn it off to sit inline beside a field. */
  fullWidth?: boolean;
};

const BASE =
  "min-h-12 rounded px-4 font-slab text-[15px] tracking-[0.04em] -skew-x-7 uppercase " +
  "cursor-pointer transition-colors disabled:cursor-not-allowed disabled:opacity-60 " +
  "focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-stock";

const VARIANTS = {
  solid: "bg-stock text-ink hover:bg-[#fffdf7]",
  ghost: "bg-transparent text-fg ring-1 ring-line ring-inset hover:bg-table-raised",
} as const;

export function Button({
  variant = "solid",
  fullWidth = true,
  className = "",
  ...props
}: Props) {
  return (
    <button
      {...props}
      className={`${BASE} ${VARIANTS[variant]} ${fullWidth ? "block w-full" : "shrink-0"} ${className}`}
    />
  );
}
