import type { Metadata } from "next";

import { ListBuilder } from "@/components/foundation/content/lists/ListSummaries";
import { ListsChrome } from "@/components/foundation/content/lists/ListsChrome";
import { ButtonLink } from "@/components/foundation/ui-kit/Button";
import { EmptyState } from "@/components/foundation/ui-kit/EmptyState";
import { PageHeader } from "@/components/foundation/ui-kit/PageHeader";
import { canViewProfile, chromeIdentity } from "@/lib/foundation/identity/viewer";
import { fetchListKinds, fetchListPlayers, fetchLists } from "@/lib/foundation/lists/server";
import { createClient } from "@/lib/supabase/server";

export const metadata: Metadata = { title: "Lists", robots: { index: false } };

/** Where a player builds their lists: Power Rankings and the position lists. */
export default async function ListsPage() {
  const supabase = await createClient();
  const { data } = await supabase.auth.getClaims();
  const claims = data?.claims;

  if (!canViewProfile(claims)) {
    return (
      <ListsChrome chrome={chromeIdentity(claims, null)}>
        <PageHeader eyebrow="Lists" title="Rank your way" />
        <EmptyState title="Lists need an account" className="mt-6">
          Create an account to rank teams and players, keep a history, and share updates with friends.
        </EmptyState>
        <div className="mt-4 max-w-xs">
          <ButtonLink href="/profile">Create an account</ButtonLink>
        </div>
      </ListsChrome>
    );
  }

  const { data: profile } = await supabase.from("profiles").select("display_name, avatar_url, username").eq("id", claims!.sub).single();
  const chrome = chromeIdentity(claims, profile);
  const [kinds, owned] = await Promise.all([
    fetchListKinds(supabase),
    profile?.username ? fetchLists(supabase, profile.username) : Promise.resolve({ lists: [], failed: false }),
  ]);
  const players = await fetchListPlayers(supabase, owned.lists.filter((list) => list.itemKind === "player").flatMap((list) => list.items.slice(0, 3)));

  return (
    <ListsChrome chrome={chrome}>
      <PageHeader eyebrow="Lists" title="Your lists" description="Rank teams and players. Every version you save stays in your history, and friends can see how your lists change." />
      {!profile?.username ? (
        <EmptyState title="Pick a username first" className="mt-6">
          Lists live on your profile, which needs a username.{" "}
          <a href="/profile" className="text-fg underline underline-offset-2">Open your profile</a>
        </EmptyState>
      ) : owned.failed ? (
        <EmptyState title="Couldn't load your lists" className="mt-6">Try again in a moment.</EmptyState>
      ) : (
        <ListBuilder kinds={kinds} lists={owned.lists} players={players} />
      )}
    </ListsChrome>
  );
}
