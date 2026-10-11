import Link from "next/link";

import { PageShell } from "@/components/foundation/ui-kit/PageShell";
import { Sidebar } from "@/components/foundation/ui-kit/Sidebar";
import { DashboardHeader } from "@/components/home/DashboardHeader";

/** What a leaderboard page shows a signed-out visitor or a guest: a way in, then back to `next`. */
export function SignedOutLeaderboard({ next, body }: { next: string; body: string }) {
  return (
    <>
      <Sidebar />
      <DashboardHeader displayName={null} email={null} avatarUrl={null} />
      <PageShell variant="dashboard">
        <section className="max-w-xl">
          <p className="type-label text-hidden-text">Leaderboard</p>
          <h1 className="mt-3 font-slab text-[36px] leading-[.96] uppercase sm:text-[46px]">See where you rank</h1>
          <p className="mt-4 text-[15px] leading-6 text-fg-muted">{body}</p>
          <Link
            href={`/login?next=${encodeURIComponent(next)}`}
            className="mt-6 inline-flex rounded-card bg-fg px-4 py-3 type-label font-bold text-surface focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-fg"
          >
            Sign in
          </Link>
        </section>
      </PageShell>
    </>
  );
}
