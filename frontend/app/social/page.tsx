import { ColumnHead } from "@/components/home/ColumnHead";
import { TalkPreview } from "@/components/home/TalkPreview";
import { TopBar } from "@/components/layout/TopBar";
import { createClient } from "@/lib/supabase/server";
import { isSignedInViewer } from "@/lib/auth/viewer";

/**
 * Social's own route — split out of the home page once Party, Solo and
 * Social each got a top-bar link of their own (see
 * components/layout/TopBar.tsx). There is nothing to do here yet: see
 * TalkPreview for why that stays an honest placeholder rather than a mocked-up
 * feature.
 */
export default async function SocialPage() {
  const supabase = await createClient();

  const { data } = await supabase.auth.getClaims();
  const claims = data?.claims;

  const viewer = isSignedInViewer(claims);

  const { data: profile } = viewer
    ? await supabase.from("profiles").select("display_name").eq("id", claims!.sub).single()
    : { data: null };

  const displayName = profile?.display_name ?? (viewer ? (claims!.email as string) : null);

  return (
    <>
      <TopBar displayName={displayName} />

      <main className="mx-auto w-full max-w-7xl flex-1 px-4 pb-16 sm:px-6 lg:px-8 lg:pb-20">
        <section className="pt-10 lg:pt-14">
          <ColumnHead as="h1" id="social-heading" title="Social" meta="In development" />
          <TalkPreview />
        </section>
      </main>
    </>
  );
}
