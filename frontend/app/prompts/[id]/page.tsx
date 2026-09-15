import { notFound, redirect } from "next/navigation";

import { DashboardHeader } from "@/components/home/DashboardHeader";
import { Sidebar } from "@/components/layout/Sidebar";
import { PostHeroHeader } from "@/components/social/PostHeroHeader";
import { PromptContext } from "@/components/social/PromptContext";
import { PromptThread } from "@/components/social/PromptThread";
import { isSignedInViewer } from "@/lib/auth/viewer";
import { fetchPromptById } from "@/lib/prompts/feed";
import { createClient } from "@/lib/supabase/server";

/** A prompt's shareable, reload-safe detail screen. */
export default async function PromptDetailPage(props: PageProps<"/prompts/[id]">) {
  const { id } = await props.params;
  const supabase = await createClient();
  const { data } = await supabase.auth.getClaims();
  const claims = data?.claims;

  if (!isSignedInViewer(claims)) {
    redirect(`/login?next=${encodeURIComponent(`/prompts/${id}`)}`);
  }

  const [profileResult, post] = await Promise.all([
    supabase.from("profiles").select("display_name, avatar_url").eq("id", claims.sub).single(),
    fetchPromptById(supabase, claims.sub, id),
  ]);
  if (!post) notFound();

  const displayName = profileResult.data?.display_name ?? (claims.email as string) ?? "You";
  const email = (claims.email as string | undefined) ?? null;
  const avatarUrl = profileResult.data?.avatar_url ?? null;

  return (
    <>
      <Sidebar displayName={displayName} email={email} avatarUrl={avatarUrl} canPlaySolo />
      <DashboardHeader displayName={displayName} email={email} avatarUrl={avatarUrl} />
      <main data-prompt-detail className="app-page flex-1">
        <div data-prompt-layout className="grid gap-10 xl:grid-cols-[minmax(0,1fr)_18rem] xl:gap-12">
          <div className="mx-auto w-full max-w-[1080px] xl:mx-0">
            <PostHeroHeader post={post} />
            <PromptThread post={post} displayName={displayName} avatarUrl={avatarUrl} />
          </div>
          <PromptContext post={post} />
        </div>
      </main>
    </>
  );
}
