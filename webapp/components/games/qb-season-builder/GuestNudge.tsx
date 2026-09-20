import Link from "next/link";

/**
 * A guest plays a whole run and gets a working share link, but their identity is
 * browser-bound: the durable history is the account feature. Shown on the pick
 * screen and again on their finished season, so it is one piece of wording.
 */
export function GuestNudge({ className = "" }: { className?: string }) {
  return (
    <p className={className}>
      Playing as a guest.{" "}
      <Link href="/settings" className="text-fg underline decoration-line underline-offset-4 hover:decoration-fg">
        Create an account
      </Link>{" "}
      to keep your runs.
    </p>
  );
}
