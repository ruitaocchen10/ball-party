import type { Metadata } from "next";
import { notFound } from "next/navigation";

import { DashboardHeader } from "@/components/home/DashboardHeader";
import { Sidebar } from "@/components/foundation/ui-kit/Sidebar";
import { PostHeroHeader } from "@/components/foundation/content/prompts/PostHeroHeader";
import { PromptContext } from "@/components/foundation/content/prompts/PromptContext";
import { TakeThread } from "@/components/foundation/content/prompts/TakeThread";
import { canAnswerPrompt, chromeIdentity, isSignedInViewer } from "@/lib/foundation/identity/viewer";
import { fetchPromptById } from "@/lib/foundation/content/prompts/feed";
import { fetchPromptMeta } from "@/lib/foundation/content/prompts/meta";
import { createClient } from "@/lib/supabase/server";
import { PageShell } from "@/components/foundation/ui-kit/PageShell";

/**
 * A take is one player's words under their display name — thin, user-written
 * and not something to put in a search index, so these pages are `noindex`
 * (links still followed, so the prompt itself is discovered). A shared take
 * link still unfurls with the prompt's preview card, which comes from the
 * parent segment's opengraph-image. That only works because this leaves
 * `openGraph` unset: a child that sets it drops the images inherited from its
 * ancestors, while Next fills og:title and og:description from these fields.
 */
export async function generateMetadata(props: PageProps<"/prompts/[id]/takes/[takeId]">): Promise<Metadata> {
  const { id } = await props.params;
  const meta = await fetchPromptMeta(id);
  const robots = { index: false, follow: true };
  if (!meta) return { title: "Take not found", robots };

  return { title: `Take on ${meta.title}`, description: meta.description, robots };
}

/** Focused discussion screen for an individual take. */
export default async function TakeDetailPage(props: PageProps<"/prompts/[id]/takes/[takeId]">) {
  const { id, takeId } = await props.params;
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
  const take = post?.comments.find((comment) => comment.id === takeId);
  if (!post || !take) notFound();

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
      <PageShell variant="dashboard" data-prompt-detail>
        <div data-prompt-layout className="grid gap-10 xl:grid-cols-[minmax(0,1fr)_18rem] xl:gap-12">
          <div className="mx-auto w-full max-w-[1080px] xl:mx-0">
            <PostHeroHeader post={post} backHref={`/prompts/${id}`} backLabel="All takes" />
            <TakeThread post={post} take={take} displayName={displayName} avatarUrl={avatarUrl} viewerCanAnswer={canAnswerPrompt(claims)} />
          </div>
          <PromptContext post={post} />
        </div>
      </PageShell>
    </>
  );
}
