import type { Metadata } from "next";
import Link from "next/link";

import { FriendsManager, friendsDataFromRows } from "@/components/foundation/friends/FriendsManager";
import { DashboardHeader } from "@/components/home/DashboardHeader";
import { PageHeader } from "@/components/foundation/ui-kit/PageHeader";
import { PageShell } from "@/components/foundation/ui-kit/PageShell";
import { Sidebar } from "@/components/foundation/ui-kit/Sidebar";
import { EmptyState } from "@/components/foundation/ui-kit/EmptyState";
import { canViewProfile, chromeIdentity, isSignedInViewer } from "@/lib/foundation/identity/viewer";
import { createClient } from "@/lib/supabase/server";

export const metadata: Metadata = { title: "Friends" };

/** Friends, requests, search and your invite link. Needs a real account. */
export default async function FriendsPage() {
  const supabase = await createClient();
  const { data } = await supabase.auth.getClaims();
  const claims = data?.claims;

  // The proxy sends signed-out visitors to /login?next=/friends; a guest has a
  // session but no account, and guests cannot have friends.
  if (!isSignedInViewer(claims) || !canViewProfile(claims)) return <GuestFriends />;

  const [{ data: profile }, friends, requests, blocked, code] = await Promise.all([
    supabase.from("profiles").select("display_name, avatar_url").eq("id", claims.sub).single(),
    supabase.rpc("list_friends"),
    supabase.rpc("list_friend_requests"),
    supabase.rpc("list_blocked_users"),
    supabase.rpc("get_my_friend_code"),
  ]);
  const { displayName, email, avatarUrl } = chromeIdentity(claims, profile);
  const failed = friends.error || requests.error || blocked.error;

  return (
    <>
      <Sidebar displayName={displayName} email={email} avatarUrl={avatarUrl} />
      <DashboardHeader displayName={displayName} email={email} avatarUrl={avatarUrl} />
      <PageShell variant="dashboard">
        <PageHeader eyebrow="Friends" title="Your crew" description="Find friends, answer requests and share your invite link." />
        {failed ? (
          <EmptyState title="Couldn't load your friends" className="mt-6">Try again in a moment.</EmptyState>
        ) : (
          <FriendsManager
            initial={friendsDataFromRows(friends.data ?? [], requests.data ?? [], blocked.data ?? [])}
            inviteCode={code.error ? null : code.data}
          />
        )}
      </PageShell>
    </>
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
