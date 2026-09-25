import Link from "next/link";

/**
 * A guest plays a whole run and gets a working share link, but their identity is
 * browser-bound and their runs are swept after 30 days (migration 0155): the
 * durable history is the account feature. Making an account does not carry the
 * guest's existing runs over — it is a separate user — so the promise is about
 * runs from then on. Shown on the pick screen and again on their finished
 * season, so it is one piece of wording.
 */
export function GuestNudge({ className = "" }: { className?: string }) {
  return (
    <p className={className}>
      Playing as a guest, so runs are deleted after 30 days.{" "}
      <Link href="/settings" className="text-fg underline decoration-line underline-offset-4 hover:decoration-fg">
        Create an account
      </Link>{" "}
      to keep future runs.
    </p>
  );
}
