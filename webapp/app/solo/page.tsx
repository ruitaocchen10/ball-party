import type { Metadata } from "next";

import { DashboardHeader } from "@/components/home/DashboardHeader";
import { SoloGrid } from "@/components/home/SoloGrid";
import { ErrorBanner } from "@/components/foundation/ui-kit/ErrorBanner";
import { PageHeader } from "@/components/foundation/ui-kit/PageHeader";
import { Sidebar } from "@/components/foundation/ui-kit/Sidebar";
import { createClient } from "@/lib/supabase/server";
import { isSignedInViewer } from "@/lib/foundation/identity/viewer";

// A sign-up destination rather than a landing page (see below), so it stays out
// of the index until it earns its own content.
export const metadata: Metadata = { title: "Solo games", robots: { index: false } };

/**
 * The games a lone player can start right now, on its own route — split out
 * of the home page once Party, Solo and Social each had a section of their
 * own. No lobby to start or join here, so this page skips straight to the
 * grid rather than carrying Party's two-panel action strip.
 *
 * No longer linked from the sidebar's main nav: the rail's own Solo games
 * section (see components/layout/Sidebar.tsx) starts a game in one click, so
 * this grid stopped being the fastest way in. The route stays live as the
 * sign-up destination for a signed-out visitor who clicks a solo game there,
 * and for anyone who lands on it directly.
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

  return (
    <>
      <Sidebar displayName={displayName} email={email} avatarUrl={avatarUrl} canPlaySolo={viewer} />
      <DashboardHeader displayName={displayName} email={email} avatarUrl={avatarUrl} />

      <main className="app-page flex-1">
        {errorText ? <ErrorBanner>{errorText}</ErrorBanner> : null}

        <div className="mx-auto w-full max-w-[1080px]">
          <PageHeader
            eyebrow="Solo"
            title="Play on your own"
            description="Pick a game and jump in whenever you’re ready."
          />

          <section className="mt-9" aria-label="Solo games">
            <SoloGrid canPlaySolo={viewer} />
          </section>
        </div>
      </main>
    </>
  );
}
