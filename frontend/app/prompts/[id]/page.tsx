import { notFound } from "next/navigation";

import { DashboardHeader } from "@/components/home/DashboardHeader";
import { Sidebar } from "@/components/foundation/ui-kit/Sidebar";
import { PostHeroHeader } from "@/components/foundation/content/prompts/PostHeroHeader";
import { PromptContext } from "@/components/foundation/content/prompts/PromptContext";
import { PromptThread } from "@/components/foundation/content/prompts/PromptThread";
import { canAnswerPrompt, isSignedInViewer } from "@/lib/foundation/identity/viewer";
import { fetchPromptById } from "@/lib/foundation/content/prompts/feed";
import { createClient } from "@/lib/supabase/server";

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

  const displayName = profileResult.data?.display_name ?? (viewer ? (claims.email as string) : "Player") ?? "Player";
  const email = viewer ? ((claims.email as string | undefined) ?? null) : null;
  const avatarUrl = profileResult.data?.avatar_url ?? null;

  return (
    <>
      <Sidebar displayName={viewer ? displayName : null} email={email} avatarUrl={avatarUrl} canPlaySolo={viewer} />
      <DashboardHeader displayName={viewer ? displayName : null} email={email} avatarUrl={avatarUrl} />
      <main data-prompt-detail className="app-page flex-1">
        <div data-prompt-layout className="grid gap-10 xl:grid-cols-[minmax(0,1fr)_18rem] xl:gap-12">
          <div className="mx-auto w-full max-w-[1080px] xl:mx-0">
            <PostHeroHeader post={post} />
            <PromptThread post={post} displayName={displayName} avatarUrl={avatarUrl} viewerCanAnswer={canAnswerPrompt(claims)} />
          </div>
          <PromptContext post={post} />
        </div>
      </main>
    </>
  );
}
