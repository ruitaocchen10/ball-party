import type { Metadata } from "next";
import Link from "next/link";
import { redirect } from "next/navigation";

import { ProfileFriendActions } from "@/components/foundation/friends/ProfileFriendActions";
import { ProfileHeader } from "@/components/foundation/identity/ProfileHeader";
import { ProfileHighlightsCard } from "@/components/foundation/identity/ProfileHighlights";
import { DashboardHeader } from "@/components/home/DashboardHeader";
import { ButtonLink } from "@/components/foundation/ui-kit/Button";
import { EmptyState } from "@/components/foundation/ui-kit/EmptyState";
import { PageShell } from "@/components/foundation/ui-kit/PageShell";
import { Sidebar } from "@/components/foundation/ui-kit/Sidebar";
import { parseRelationship } from "@/lib/foundation/friends/friends";
import { joinedMonth, profileHighlights } from "@/lib/foundation/identity/highlights";
import { completedMatchesFromHistory } from "@/lib/foundation/identity/summary";
import { canViewProfile, chromeIdentity, isSignedInViewer } from "@/lib/foundation/identity/viewer";
import { createClient } from "@/lib/supabase/server";

// Static on purpose: the title must not reveal whether a username exists.
export const metadata: Metadata = { title: "Player profile", robots: { index: false } };

/**
 * Another player's profile, found by username. Visibility is decided in SQL
 * (`get_profile`, `can_view`): public profiles open for any account, private
 * ones only for friends, and everyone else gets the header and a way to ask.
 * A missing user, a guest account and a player who blocked you all come back
 * as no row, so they share one neutral not-found page.
 */
export default async function PlayerProfilePage(props: PageProps<"/u/[username]">) {
  const { username } = await props.params;
  const supabase = await createClient();
  const { data } = await supabase.auth.getClaims();
  const claims = data?.claims;

  // Signed-out visitors are sent to /login?next=/u/<name> by the proxy.
  if (!isSignedInViewer(claims) || !canViewProfile(claims)) {
    return (
      <Chrome>
        <PlayerNotFound />
      </Chrome>
    );
  }

  const [{ data: viewer }, { data: rows }] = await Promise.all([
    supabase.from("profiles").select("display_name, avatar_url").eq("id", claims.sub).single(),
    supabase.rpc("get_profile", { p_username: decodeURIComponent(username) }),
  ]);
  const chrome = chromeIdentity(claims, viewer);
  const profile = rows?.[0];

  if (!profile) {
    return (
      <Chrome chrome={chrome}>
        <PlayerNotFound />
      </Chrome>
    );
  }

  const relationship = parseRelationship(profile.relationship);
  if (relationship === "self") redirect("/profile");

  const [knower, history] = profile.can_view
    ? await Promise.all([
        supabase.rpc("get_profile_knower_highlights", { p_profile_id: profile.profile_id }),
        supabase.rpc("get_profile_match_history", { p_profile_id: profile.profile_id }),
      ])
    : [null, null];

  return (
    <Chrome chrome={chrome}>
      <ProfileHeader
        displayName={profile.display_name}
        avatarUrl={profile.avatar_url}
        username={profile.username}
        joinedLabel={`Playing since ${joinedMonth(profile.member_since)}`}
        action={
          <ProfileFriendActions
            profileId={profile.profile_id}
            username={profile.username}
            displayName={profile.display_name}
            relationship={relationship}
          />
        }
      />
      {knower && history ? (
        knower.error || history.error ? (
          <EmptyState title="Couldn't load this profile" className="mt-6">Try again in a moment.</EmptyState>
        ) : (
          <ProfileHighlightsCard
            highlights={profileHighlights(completedMatchesFromHistory(history.data ?? []), knower.data ?? [])}
          />
        )
      ) : (
        <EmptyState title="Private profile" className="mt-6">
          Only friends can see this profile.
          {relationship === "none" ? " Add them as a friend to ask for access." : null}
          {relationship === "outgoing" ? " Your request is waiting for them." : null}
          {relationship === "incoming" ? " They asked to be your friend. Accept to see their profile." : null}
        </EmptyState>
      )}
    </Chrome>
  );
}

function Chrome({
  chrome,
  children,
}: {
  chrome?: { displayName: string | null; email: string | null; avatarUrl: string | null };
  children: React.ReactNode;
}) {
  return (
    <>
      <Sidebar displayName={chrome?.displayName} email={chrome?.email} avatarUrl={chrome?.avatarUrl} />
      <DashboardHeader displayName={chrome?.displayName ?? null} email={chrome?.email ?? null} avatarUrl={chrome?.avatarUrl ?? null} />
      <PageShell variant="dashboard">{children}</PageShell>
    </>
  );
}

function PlayerNotFound() {
  return (
    <section className="max-w-xl">
      <p className="type-label text-hidden-text">Player profile</p>
      <h1 className="mt-3 font-slab text-[36px] leading-[.96] uppercase sm:text-[46px]">Player not found</h1>
      <p className="mt-4 text-[15px] leading-6 text-fg-muted">
        We couldn&apos;t find that player. Check the username, or find friends from your friends page.
      </p>
      <div className="mt-6 max-w-xs">
        <ButtonLink href="/friends">Go to friends</ButtonLink>
      </div>
      <Link href="/" className="mt-4 inline-block type-label text-fg-muted underline underline-offset-2 hover:text-fg">
        Back home
      </Link>
    </section>
  );
}
