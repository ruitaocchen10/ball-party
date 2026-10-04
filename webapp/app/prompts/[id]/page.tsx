import type { Metadata } from "next";
import { notFound } from "next/navigation";

import { DashboardHeader } from "@/components/home/DashboardHeader";
import { Sidebar } from "@/components/foundation/ui-kit/Sidebar";
import { PostHeroHeader } from "@/components/foundation/content/prompts/PostHeroHeader";
import { PromptContext } from "@/components/foundation/content/prompts/PromptContext";
import { PromptThread } from "@/components/foundation/content/prompts/PromptThread";
import { canAnswerPrompt, chromeIdentity, isSignedInViewer } from "@/lib/foundation/identity/viewer";
import { fetchBoldPredictionBoard } from "@/lib/foundation/content/prompts/boldFeed";
import { fetchPromptById } from "@/lib/foundation/content/prompts/feed";
import { fetchPromptMeta } from "@/lib/foundation/content/prompts/meta";
import { SITE_NAME } from "@/lib/seo/site";
import { createClient } from "@/lib/supabase/server";

/**
 * What a search result or a shared link shows for this prompt. Reads only the
 * post row — not the full feed the page itself loads — and the sibling
 * opengraph-image.tsx draws the preview card from the same row.
 */
export async function generateMetadata(props: PageProps<"/prompts/[id]">): Promise<Metadata> {
  const { id } = await props.params;
  const meta = await fetchPromptMeta(id);
  if (!meta) return { title: "Prompt not found", robots: { index: false } };

  const canonical = `/prompts/${id}`;
  return {
    title: meta.title,
    description: meta.description,
    alternates: { canonical },
    // Replaces the root layout's openGraph wholesale, so siteName and type come along.
    openGraph: { type: "website", siteName: SITE_NAME, title: meta.title, description: meta.description, url: canonical },
  };
}

/** A prompt's shareable, reload-safe detail screen. */
export default async function PromptDetailPage(props: PageProps<"/prompts/[id]">) {
  const { id } = await props.params;
  const supabase = await createClient();
  const { data } = await supabase.auth.getClaims();
  const claims = data?.claims;

  const viewer = isSignedInViewer(claims);
  const [profileResult, post] = await Promise.all([
    viewer
      ? supabase.from("profiles").select("display_name, avatar_url").eq("id", claims.sub).single()
      : Promise.resolve({ data: null }),
    fetchPromptById(supabase, viewer ? claims.sub : null, id),
  ]);
  if (!post) notFound();
  const boldPredictions = post.templateKind === "bold_predictions" ? await fetchBoldPredictionBoard(supabase, post, viewer ? claims.sub : null) : undefined;

  // The thread composes as the viewer, so it keeps the name and avatar a
  // guest's placeholder profile has; the header and sidebar do not (see
  // chromeIdentity), because a guest is not shown as an account there.
  const displayName = profileResult.data?.display_name ?? (viewer ? (claims.email as string) : "Player") ?? "Player";
  const avatarUrl = profileResult.data?.avatar_url ?? null;
  const chrome = chromeIdentity(claims, profileResult.data);

  return (
    <>
      <Sidebar displayName={chrome.displayName} email={chrome.email} avatarUrl={chrome.avatarUrl} />
      <DashboardHeader displayName={chrome.displayName} email={chrome.email} avatarUrl={chrome.avatarUrl} />
      <main data-prompt-detail className="app-page flex-1">
        <div data-prompt-layout className="grid gap-10 xl:grid-cols-[minmax(0,1fr)_18rem] xl:gap-12">
          <div className="mx-auto w-full max-w-[1080px] xl:mx-0">
            <PostHeroHeader post={post} />
            <PromptThread post={post} displayName={displayName} avatarUrl={avatarUrl} viewerCanAnswer={canAnswerPrompt(claims)} boldPredictions={boldPredictions} />
          </div>
          <PromptContext post={post} />
        </div>
      </main>
    </>
  );
}
