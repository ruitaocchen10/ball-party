import type { Metadata } from "next";
import { notFound } from "next/navigation";

import { ListHistory } from "@/components/foundation/content/lists/ListHistory";
import { ListRows } from "@/components/foundation/content/lists/ListRows";
import { ListsChrome } from "@/components/foundation/content/lists/ListsChrome";
import { Card } from "@/components/foundation/ui-kit/Card";
import { EmptyState } from "@/components/foundation/ui-kit/EmptyState";
import { PageHeader } from "@/components/foundation/ui-kit/PageHeader";
import { parseRelationship } from "@/lib/foundation/friends/friends";
import { canViewProfile, chromeIdentity } from "@/lib/foundation/identity/viewer";
import { fetchListHistory, fetchListKinds, fetchListPlayers } from "@/lib/foundation/lists/server";
import { createClient } from "@/lib/supabase/server";

// Static on purpose: the title must not reveal whether a username exists.
export const metadata: Metadata = { title: "Player list", robots: { index: false } };

/**
 * Another player's list and its history. What the viewer sees is decided in
 * SQL (get_ranking_list): the list for anyone who can open the profile, the
 * notes and shared-update markers only for the player's friends.
 */
export default async function PlayerListPage(props: PageProps<"/u/[username]/lists/[kind]">) {
  const { username: rawUsername, kind: kindId } = await props.params;
  const username = decodeURIComponent(rawUsername);
  const supabase = await createClient();
  const { data } = await supabase.auth.getClaims();
  const claims = data?.claims;
  if (!canViewProfile(claims)) notFound();

  const [{ data: viewer }, { data: rows }, kinds] = await Promise.all([
    supabase.from("profiles").select("display_name, avatar_url").eq("id", claims!.sub).single(),
    supabase.rpc("get_profile", { p_username: username }),
    fetchListKinds(supabase),
  ]);
  const profile = rows?.[0];
  const kind = kinds.find((candidate) => candidate.id === kindId);
  if (!profile || !kind) notFound();

  const relationship = parseRelationship(profile.relationship);
  const close = relationship === "friends" || relationship === "self";
  const history = profile.can_view ? await fetchListHistory(supabase, username, kind.id) : { versions: [], failed: false };
  const players = await fetchListPlayers(supabase, kind.itemKind === "player" ? history.versions.flatMap((version) => version.items) : []);
  const current = history.versions.find((version) => version.isCurrent) ?? history.versions[0];

  return (
    <ListsChrome chrome={chromeIdentity(claims, viewer)}>
      <PageHeader
        eyebrow={profile.display_name}
        title={kind.label}
        backHref={`/u/${encodeURIComponent(username)}?tab=lists`}
        backLabel={`${profile.display_name}'s profile`}
      />
      {!profile.can_view ? (
        <EmptyState title="Private profile" className="mt-6">Only friends can see this player&apos;s lists.</EmptyState>
      ) : history.failed ? (
        <EmptyState title="Couldn't load this list" className="mt-6">Try again in a moment.</EmptyState>
      ) : !current ? (
        <EmptyState title="No list yet" className="mt-6">{profile.display_name} hasn&apos;t ranked this one.</EmptyState>
      ) : (
        <>
          <section aria-label="Current list" className="mt-5">
            <Card>
              <div className="flex items-baseline justify-between px-3 pt-3 pb-3">
                <span className="font-slab text-2xl leading-none uppercase">Current list</span>
                <span className="type-label text-panel-muted">Version {current.versionNo}</span>
              </div>
              <div className="border-t border-panel-line">
                <ListRows items={current.items} itemKind={kind.itemKind} players={players} />
              </div>
            </Card>
          </section>
          <section aria-labelledby="history-heading" className="mt-10">
            <h2 id="history-heading" className="type-label font-bold text-fg-muted">History</h2>
            <div className="mt-3">
              <ListHistory versions={history.versions} itemKind={kind.itemKind} players={players} close={close} />
            </div>
          </section>
        </>
      )}
    </ListsChrome>
  );
}
