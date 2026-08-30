import { ColumnHead } from "@/components/home/ColumnHead";
import { SoloGrid } from "@/components/home/SoloGrid";
import { ErrorBanner } from "@/components/ui/ErrorBanner";
import { GAMES } from "@/lib/games/catalog";
import { Sidebar } from "@/components/layout/Sidebar";
import { createClient } from "@/lib/supabase/server";
import { isSignedInViewer } from "@/lib/auth/viewer";

/**
 * The games a lone player can start right now, on its own route — split out
 * of the home page once Party, Solo and Social each got a sidebar link of
 * their own (see components/layout/Sidebar.tsx). No lobby to start or join
 * here, so this page skips straight to the grid rather than carrying Party's
 * two-panel action strip.
 */
export default async function SoloPage(props: PageProps<"/solo">) {
  const supabase = await createClient();

  const { data } = await supabase.auth.getClaims();
  const claims = data?.claims;

  const viewer = isSignedInViewer(claims);

  const { data: profile } = viewer
    ? await supabase.from("profiles").select("display_name, avatar_url").eq("id", claims!.sub).single()
    : { data: null };

  const displayName = profile?.display_name ?? (viewer ? (claims!.email as string) : null);
  const email = viewer ? ((claims!.email as string | undefined) ?? null) : null;
  const avatarUrl = profile?.avatar_url ?? null;

  const { error } = await props.searchParams;
  const errorText = Array.isArray(error) ? error[0] : error;

  const soloLive = GAMES.filter((game) => game.solo && game.status === "live").length;

  return (
    <>
      <Sidebar displayName={displayName} email={email} avatarUrl={avatarUrl} />

      <main className="mx-auto w-full max-w-7xl flex-1 px-4 pb-16 sm:px-6 lg:px-8 lg:pb-20">
        {errorText ? <ErrorBanner>{errorText}</ErrorBanner> : null}

        <section className="pt-10 lg:pt-14">
          <ColumnHead as="h1" id="solo-heading" title="Solo" meta={`${soloLive} live`} />
          <SoloGrid canPlaySolo={viewer} />
        </section>
      </main>
    </>
  );
}
