import type { Metadata } from "next";
import { notFound } from "next/navigation";

import { ListUpdateCard } from "@/components/foundation/content/lists/ListUpdateCard";
import { ListUpdateThread } from "@/components/foundation/content/lists/ListUpdateThread";
import { ListsChrome } from "@/components/foundation/content/lists/ListsChrome";
import { PageHeader } from "@/components/foundation/ui-kit/PageHeader";
import { canViewProfile, chromeIdentity } from "@/lib/foundation/identity/viewer";
import { fetchListPlayers, fetchListThread, fetchListUpdate } from "@/lib/foundation/lists/server";
import { createClient } from "@/lib/supabase/server";

export const metadata: Metadata = { title: "List update", robots: { index: false } };

const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

/**
 * A friend's published list edit and the replies under it. Update cards are
 * friends-only, so anyone else gets the same not-found as a card that does not exist.
 */
export default async function ListUpdatePage(props: PageProps<"/lists/updates/[postId]">) {
  const { postId } = await props.params;
  const supabase = await createClient();
  const { data } = await supabase.auth.getClaims();
  const claims = data?.claims;
  if (!canViewProfile(claims) || !UUID.test(postId)) notFound();

  const [{ data: viewer }, update] = await Promise.all([
    supabase.from("profiles").select("display_name, avatar_url").eq("id", claims!.sub).single(),
    fetchListUpdate(supabase, postId),
  ]);
  if (!update) notFound();

  const [players, thread] = await Promise.all([
    fetchListPlayers(supabase, update.itemKind === "player" ? [...update.items, ...(update.previousItems ?? [])] : []),
    fetchListThread(supabase, postId, claims!.sub),
  ]);
  const chrome = chromeIdentity(claims, viewer);

  return (
    <ListsChrome chrome={chrome}>
      <PageHeader eyebrow="Lists" title={`${update.label} update`} backHref="/?filter=lists" backLabel="Home" />
      <div className="mt-5">
        <ListUpdateCard update={update} players={players} viewerId={claims!.sub} full>
          <ListUpdateThread postId={postId} takeId={thread.takeId} replies={thread.replies} displayName={chrome.displayName ?? "You"} avatarUrl={chrome.avatarUrl} />
        </ListUpdateCard>
      </div>
    </ListsChrome>
  );
}
