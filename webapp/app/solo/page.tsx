import type { Metadata } from "next";

import { DashboardHeader } from "@/components/home/DashboardHeader";
import { SoloGrid } from "@/components/home/SoloGrid";
import { ErrorBanner } from "@/components/foundation/ui-kit/ErrorBanner";
import { PageHeader } from "@/components/foundation/ui-kit/PageHeader";
import { Sidebar } from "@/components/foundation/ui-kit/Sidebar";
import { createClient } from "@/lib/supabase/server";
import { chromeIdentity, isSignedInViewer } from "@/lib/foundation/identity/viewer";
import { PageShell } from "@/components/foundation/ui-kit/PageShell";

// A place to pick settings rather than a landing page (see below), so it stays
// out of the index until it earns its own content.
export const metadata: Metadata = { title: "Solo games", robots: { index: false } };

/**
 * The games a lone player can start right now, on its own route — split out
 * of the home page once Party, Solo and Social each had a section of their
 * own. No lobby to start or join here, so this page skips straight to the
 * grid rather than carrying Party's two-panel action strip.
 *
 * No longer linked from the sidebar's main nav: the rail's own Solo games
 * section (see components/layout/Sidebar.tsx) starts a game in one click, so
 * this grid stopped being the fastest way in. The route stays live as where a
 * game with start-time settings is set up, and for anyone who lands on it
 * directly. Signed out is fine: starting a run gives the visitor a guest
 * session (see `playSolo`).
 */
export default async function SoloPage(props: PageProps<"/solo">) {
  const supabase = await createClient();

  const { data } = await supabase.auth.getClaims();
  const claims = data?.claims;

  const viewer = isSignedInViewer(claims);

  const { data: profile } = viewer
    ? await supabase.from("profiles").select("display_name, avatar_url").eq("id", claims!.sub).single()
    : { data: null };

  const { displayName, email, avatarUrl } = chromeIdentity(claims, profile);

  // Only a signed-in viewer can play, so only they pay for the bounds behind
  // Higher or Lower's era picker. A failure is not fatal: the picker drops out
  // and the dealer falls back to the whole pool.
  const { data: era } = viewer
    ? await (supabase.schema("higher_or_lower").rpc("season_bounds" as never) as unknown as Promise<{
      data: { season_min: number; season_max: number } | null;
    }>)
    : { data: null };
  const higherOrLowerEra = era?.season_min != null && era.season_max != null
    ? { seasonMin: era.season_min, seasonMax: era.season_max }
    : null;

  const { error } = await props.searchParams;
  const errorText = Array.isArray(error) ? error[0] : error;

  return (
    <>
      <Sidebar displayName={displayName} email={email} avatarUrl={avatarUrl} />
      <DashboardHeader displayName={displayName} email={email} avatarUrl={avatarUrl} />

      <PageShell variant="dashboard">
        {errorText ? <ErrorBanner>{errorText}</ErrorBanner> : null}

        <div className="mx-auto w-full max-w-[1080px]">
          <PageHeader
            eyebrow="Solo"
            title="Play on your own"
            description="Pick a game and jump in whenever you’re ready."
          />

          <section className="mt-9" aria-label="Solo games">
            <SoloGrid higherOrLowerEra={higherOrLowerEra} />
          </section>
        </div>
      </PageShell>
    </>
  );
}
