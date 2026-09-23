import type { Metadata } from "next";
import { notFound } from "next/navigation";

import { QbSeasonBuilderResult } from "@/components/games/qb-season-builder/QbSeasonBuilderResult";
import { DashboardHeader } from "@/components/home/DashboardHeader";
import { Sidebar } from "@/components/foundation/ui-kit/Sidebar";
import { isGuestViewer, isSignedInViewer } from "@/lib/foundation/identity/viewer";
import { fetchPersonalBest, fetchResult } from "@/lib/games/qb-season-builder/read";
import { shareCardFromResult } from "@/lib/games/qb-season-builder/share-card";
import { playSolo } from "@/lib/platform/lobbies/actions";
import { SITE_NAME } from "@/lib/seo/site";
import { createClient } from "@/lib/supabase/server";

/**
 * A guest's run is as shareable as an account's, and its id is all that
 * protects it, so it is not something to list in a search index.
 */
export async function generateMetadata(props: PageProps<"/solo/qb-season-builder/result/[id]">): Promise<Metadata> {
  const { id } = await props.params;
  const result = await fetchResult(await createClient(), id);
  if (!result) return { title: "QB Season Builder result not found", robots: { index: false } };

  const card = shareCardFromResult(result);
  const canonical = `/solo/qb-season-builder/result/${id}`;
  return {
    title: card.title,
    description: card.description,
    alternates: { canonical },
    robots: { index: false },
    openGraph: { type: "website", siteName: SITE_NAME, title: card.title, description: card.description, url: canonical },
  };
}

/**
 * The read-only result of a finished QB Season Builder run, for anyone with the
 * link — signed in, a guest, or nobody. It is the whole season at once: the
 * staged reveal belongs to the player who just finished, at their own run's URL.
 *
 * What is particular to the viewer is theirs, not the run's owner's: a signed-in
 * account sees its own personal best for this run's mode, a guest sees the
 * nudge to make an account, and a stranger sees neither.
 */
export default async function QbSeasonResultPage(props: PageProps<"/solo/qb-season-builder/result/[id]">) {
  const { id } = await props.params;
  const supabase = await createClient();
  const { data } = await supabase.auth.getClaims();
  const claims = data?.claims;

  const result = await fetchResult(supabase, id);
  if (!result) notFound();

  const viewer = isSignedInViewer(claims);
  const [profileResult, personalBest] = await Promise.all([
    viewer
      ? supabase.from("profiles").select("display_name, avatar_url").eq("id", claims.sub).single()
      : Promise.resolve({ data: null }),
    fetchPersonalBest(supabase, claims, result.mode),
  ]);
  const displayName = profileResult.data?.display_name ?? (viewer ? (claims.email as string | undefined) ?? null : null);
  const email = viewer ? ((claims.email as string | undefined) ?? null) : null;
  const avatarUrl = profileResult.data?.avatar_url ?? null;

  return (
    <>
      <Sidebar displayName={displayName} email={email} avatarUrl={avatarUrl} canPlaySolo={viewer} />
      <DashboardHeader displayName={displayName} email={email} avatarUrl={avatarUrl} />
      <QbSeasonBuilderResult
        result={result}
        shown={null}
        personalBest={personalBest}
        isGuest={isGuestViewer(claims)}
        staged={false}
        startNewSeason={playSolo}
      />
    </>
  );
}
