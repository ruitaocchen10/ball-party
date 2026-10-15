import type { Metadata } from "next";
import { notFound } from "next/navigation";

import { ListContext } from "@/components/foundation/content/lists/ListContext";
import { ListEditor } from "@/components/foundation/content/lists/ListEditor";
import { ListHistory } from "@/components/foundation/content/lists/ListHistory";
import { ListsChrome } from "@/components/foundation/content/lists/ListsChrome";
import { EmptyState } from "@/components/foundation/ui-kit/EmptyState";
import { PageHeader } from "@/components/foundation/ui-kit/PageHeader";
import { canViewProfile, chromeIdentity } from "@/lib/foundation/identity/viewer";
import { listTitle } from "@/lib/foundation/lists/lists";
import { fetchListHistory, fetchListKinds, fetchListPlayers, fetchOpenListPrompt } from "@/lib/foundation/lists/server";
import { createClient } from "@/lib/supabase/server";

export const metadata: Metadata = { title: "Edit a list", robots: { index: false } };

/** One of your lists: the editor on top, every saved version below it. */
export default async function EditListPage(props: PageProps<"/lists/[kind]">) {
  const { kind: kindId } = await props.params;
  const supabase = await createClient();
  const { data } = await supabase.auth.getClaims();
  const claims = data?.claims;
  if (!canViewProfile(claims)) notFound();

  const [{ data: profile }, kinds] = await Promise.all([
    supabase.from("profiles").select("display_name, avatar_url, username").eq("id", claims!.sub).single(),
    fetchListKinds(supabase),
  ]);
  const kind = kinds.find((candidate) => candidate.id === kindId);
  if (!kind || !profile?.username) notFound();

  const [history, openPromptId] = await Promise.all([
    fetchListHistory(supabase, profile.username, kind.id),
    fetchOpenListPrompt(supabase, kind.id),
  ]);
  const players = await fetchListPlayers(supabase, kind.itemKind === "player" ? history.versions.flatMap((version) => version.items) : []);
  const current = history.versions.find((version) => version.isCurrent) ?? history.versions[0];

  return (
    <ListsChrome
      chrome={chromeIdentity(claims, profile)}
      rail={<ListContext versionNo={current?.versionNo ?? null} savedAt={current?.savedAt ?? null} versionCount={history.versions.length} />}
    >
      <PageHeader
        eyebrow="Lists"
        title={`Update ${listTitle(kind, current?.items.length ?? kind.sizes[0]).replace(/^My /, "your ")}`}
        description="Your list is a living record. Change it any time, and every version stays in your history."
        backHref="/lists"
        backLabel="Your lists"
      />
      <ListEditor
        key={current?.id ?? "new"}
        kind={kind}
        saved={current?.items ?? []}
        players={players}
        openPromptId={openPromptId}
        displayName={profile.display_name ?? "You"}
        avatarUrl={profile.avatar_url ?? null}
        username={profile.username}
      />
      <section id="history" aria-labelledby="history-heading" className="mt-10">
        <h2 id="history-heading" className="type-label font-bold text-fg-muted">History</h2>
        <div className="mt-3">
          {history.failed ? (
            <EmptyState>Couldn&apos;t load your history. Try again in a moment.</EmptyState>
          ) : history.versions.length ? (
            <ListHistory versions={history.versions} itemKind={kind.itemKind} players={players} close />
          ) : (
            <EmptyState title="No versions yet">Save your first version and it starts your history.</EmptyState>
          )}
        </div>
      </section>
    </ListsChrome>
  );
}
