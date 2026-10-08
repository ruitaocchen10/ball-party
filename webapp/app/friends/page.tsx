import type { Metadata } from "next";
import Link from "next/link";

import { ActivityFeed } from "@/components/foundation/friends/ActivityFeed";
import { FriendsManager } from "@/components/foundation/friends/FriendsManager";
import { friendsDataFromRows } from "@/lib/foundation/friends/friends";
import { DashboardHeader } from "@/components/home/DashboardHeader";
import { PageHeader } from "@/components/foundation/ui-kit/PageHeader";
import { PageShell } from "@/components/foundation/ui-kit/PageShell";
import { Sidebar } from "@/components/foundation/ui-kit/Sidebar";
import { EmptyState } from "@/components/foundation/ui-kit/EmptyState";
import {
  ACTIVITY_PAGE_SIZE,
  FRIENDS_TABS,
  activityEvents,
  parseFriendsTab,
  type FriendsTab,
} from "@/lib/foundation/friends/friends";
import { canViewProfile, chromeIdentity, isSignedInViewer } from "@/lib/foundation/identity/viewer";
import { createClient } from "@/lib/supabase/server";

export const metadata: Metadata = { title: "Friends" };

/** Friends, requests, search and your invite link. Needs a real account. */
export default async function FriendsPage(props: PageProps<"/friends">) {
  const supabase = await createClient();
  const { data } = await supabase.auth.getClaims();
  const claims = data?.claims;

  // The proxy sends signed-out visitors to /login?next=/friends; a guest has a
  // session but no account, and guests cannot have friends.
  if (!isSignedInViewer(claims) || !canViewProfile(claims)) return <GuestFriends />;

  const tab = parseFriendsTab((await props.searchParams).tab);

  // The Activity tab only needs the feed and whether there are any friends (to
  // pick the right empty state); the Friends tab needs the lists and the code.
  const [{ data: profile }, friends, requests, blocked, code, activity] = await Promise.all([
    supabase.from("profiles").select("display_name, avatar_url").eq("id", claims.sub).single(),
    supabase.rpc("list_friends"),
    tab === "friends" ? supabase.rpc("list_friend_requests") : null,
    tab === "friends" ? supabase.rpc("list_blocked_users") : null,
    tab === "friends" ? supabase.rpc("get_my_friend_code") : null,
    tab === "activity" ? supabase.rpc("friend_activity", { p_limit: ACTIVITY_PAGE_SIZE }) : null,
  ]);
  const { displayName, email, avatarUrl } = chromeIdentity(claims, profile);
  const failed = friends.error || requests?.error || blocked?.error || activity?.error;

  return (
    <>
      <Sidebar displayName={displayName} email={email} avatarUrl={avatarUrl} />
      <DashboardHeader displayName={displayName} email={email} avatarUrl={avatarUrl} />
      <PageShell variant="dashboard">
        <PageHeader eyebrow="Friends" title="Your crew" description="Find friends, answer requests and share your invite link." />
        <TabNav active={tab} />
        {failed ? (
          <EmptyState title="Couldn't load your friends" className="mt-6">Try again in a moment.</EmptyState>
        ) : tab === "activity" ? (
          <ActivityFeed initial={activityEvents(activity?.data ?? [])} hasFriends={(friends.data ?? []).length > 0} />
        ) : (
          <FriendsManager
            initial={friendsDataFromRows(friends.data ?? [], requests?.data ?? [], blocked?.data ?? [])}
            inviteCode={code?.error ? null : (code?.data ?? null)}
          />
        )}
      </PageShell>
    </>
  );
}

const TAB_LABEL: Record<FriendsTab, string> = { friends: "Friends", activity: "Activity" };

function TabNav({ active }: { active: FriendsTab }) {
  return (
    <nav aria-label="Friends sections" className="mt-4 flex border border-line">
      {FRIENDS_TABS.map((key) => (
        <Link
          key={key}
          href={key === "friends" ? "/friends" : `/friends?tab=${key}`}
          aria-current={key === active ? "page" : undefined}
          className={`flex min-h-12 flex-1 items-center justify-center font-slab text-[17px] tracking-[0.04em] uppercase transition-colors focus-visible:outline-2 focus-visible:-outline-offset-2 focus-visible:outline-panel ${
            key === active ? "bg-panel text-panel-fg" : "text-fg hover:text-fg-muted"
          }`}
        >
          {TAB_LABEL[key]}
        </Link>
      ))}
    </nav>
  );
}

function GuestFriends() {
  return (
    <>
      <Sidebar />
      <DashboardHeader displayName={null} email={null} avatarUrl={null} />
      <PageShell variant="dashboard">
        <section className="max-w-xl">
          <p className="type-label text-hidden-text">Friends</p>
          <h1 className="mt-3 font-slab text-[36px] leading-[.96] uppercase sm:text-[46px]">Friends need an account</h1>
          <p className="mt-4 text-[15px] leading-6 text-fg-muted">
            Create an account to add friends, compare picks and see what they&apos;re up to.
          </p>
          <Link
            href="/signup?next=/friends"
            className="mt-6 inline-flex bg-panel px-4 py-3 type-label font-bold text-panel-fg focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-panel"
          >
            Create an account
          </Link>
        </section>
      </PageShell>
    </>
  );
}
