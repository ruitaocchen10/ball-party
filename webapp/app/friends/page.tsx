import type { Metadata } from "next";
import { redirect } from "next/navigation";

import { FriendsManager } from "@/components/foundation/friends/FriendsManager";
import { DashboardHeader } from "@/components/home/DashboardHeader";
import { EmptyState } from "@/components/foundation/ui-kit/EmptyState";
import { PageHeader } from "@/components/foundation/ui-kit/PageHeader";
import { PageShell } from "@/components/foundation/ui-kit/PageShell";
import { Sidebar } from "@/components/foundation/ui-kit/Sidebar";
import { friendsDataFromRows } from "@/lib/foundation/friends/friends";
import { canViewProfile, chromeIdentity, isSignedInViewer } from "@/lib/foundation/identity/viewer";
import { createClient } from "@/lib/supabase/server";

export const metadata: Metadata = { title: "Friends" };

/**
 * Friends, requests, adding someone and your invite link. Reached from the
 * Friends button on Profile. Friends need a real account, so a guest is sent to
 * the Profile page, which offers to create one.
 */
export default async function FriendsPage() {
  const supabase = await createClient();
  const { data } = await supabase.auth.getClaims();
  const claims = data?.claims;

  if (!isSignedInViewer(claims)) redirect("/login?next=/friends");
  if (!canViewProfile(claims)) redirect("/profile");

  const [{ data: profile }, friends, requests, blocked, code] = await Promise.all([
    supabase.from("profiles").select("display_name, avatar_url").eq("id", claims.sub).single(),
    supabase.rpc("list_friends"),
    supabase.rpc("list_friend_requests"),
    supabase.rpc("list_blocked_users"),
    supabase.rpc("get_my_friend_code"),
  ]);
  const chrome = chromeIdentity(claims, profile);
  const failed = friends.error || requests.error || blocked.error;

  return (
    <>
      <Sidebar {...chrome} />
      <DashboardHeader {...chrome} />
      <PageShell variant="dashboard">
        <PageHeader title="Your people" eyebrow="Friends" backHref="/profile" backLabel="Profile" />
        {failed ? (
          <EmptyState title="Couldn't load your friends">Try again in a moment.</EmptyState>
        ) : (
          <FriendsManager
            initial={friendsDataFromRows(friends.data ?? [], requests.data ?? [], blocked.data ?? [])}
            inviteCode={code.error ? null : (code.data ?? null)}
          />
        )}
      </PageShell>
    </>
  );
}
