import Link from "next/link";

import { PageHeader } from "@/components/foundation/ui-kit/PageHeader";
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
        <PageHeader eyebrow="Leaderboard" title="See where you rank" description={body} />
        <div className="mt-6">
          <Link
            href={`/login?next=${encodeURIComponent(next)}`}
            className="inline-flex rounded-card bg-fg px-4 py-3 type-label font-bold text-surface focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-fg"
          >
            Sign in
          </Link>
        </div>
      </PageShell>
    </>
  );
}
