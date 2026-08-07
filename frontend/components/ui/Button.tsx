import Link from "next/link";
import type { ButtonHTMLAttributes, ReactNode } from "react";

/**
 * Buttons are cream, because a button is a known thing and everything known in
 * this product sits on a light panel. `ghost` is for the subordinate action on
 * a screen — one primary per view.
 *
 * `ink` inverts that for the one place the rule breaks down: a button sitting
 * ON a cream panel, where cream-on-cream would be invisible. The colours swap;
 * the meaning doesn't.
 *
 * Focus rings are cream rather than red: red is reserved for hidden state, and
 * a focus ring is the opposite of hidden. On a panel it inverts with the rest.
 */
type Props = ButtonHTMLAttributes<HTMLButtonElement> & {
  variant?: "solid" | "ghost" | "ink";
  /** Full width is the common case; turn it off to sit inline beside a field. */
  fullWidth?: boolean;
};

const BASE =
  "min-h-12 rounded px-4 font-slab text-[15px] tracking-[0.04em] -skew-x-7 uppercase " +
  "cursor-pointer transition-colors disabled:cursor-not-allowed disabled:opacity-60 " +
  "focus-visible:outline-2 focus-visible:outline-offset-2";

const VARIANTS = {
  solid: "bg-panel text-panel-fg hover:bg-[#fffdf7] focus-visible:outline-panel",
  ghost:
    "bg-transparent text-fg ring-1 ring-line ring-inset hover:bg-surface-raised " +
    "focus-visible:outline-panel",
  ink: "bg-panel-fg text-panel hover:bg-[#2c2921] focus-visible:outline-panel-fg",
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

/**
 * A navigation that looks like a button. Separate from <Button> because a
 * <button> inside an <a> is invalid markup, and because the distinction is real
 * — this changes the URL, it does not submit anything.
 */
export function ButtonLink({
  href,
  variant = "solid",
  fullWidth = true,
  className = "",
  children,
}: {
  href: string;
  variant?: "solid" | "ghost" | "ink";
  fullWidth?: boolean;
  className?: string;
  children: ReactNode;
}) {
  return (
    <Link
      href={href}
      className={`${BASE} ${VARIANTS[variant]} inline-flex items-center justify-center ${
        fullWidth ? "flex w-full" : "shrink-0"
      } ${className}`}
    >
      {children}
    </Link>
  );
}
