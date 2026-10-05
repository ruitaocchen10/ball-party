import Link from "next/link";

import { AccountCredentials } from "@/components/foundation/identity/AccountCredentials";
import { DeleteAccountSection } from "@/components/foundation/identity/DeleteAccountSection";
import { GuestUpgrade } from "@/components/foundation/identity/GuestUpgrade";
import { RankingsVisibilityToggle } from "@/components/foundation/identity/RankingsVisibilityToggle";
import { PageHeader } from "@/components/foundation/ui-kit/PageHeader";
import { Sidebar } from "@/components/foundation/ui-kit/Sidebar";
import { DashboardHeader } from "@/components/home/DashboardHeader";
import { canViewProfile, isSignedInViewer } from "@/lib/foundation/identity/viewer";
import { createClient } from "@/lib/supabase/server";

/** Account-level controls that don't belong on the public /profile page:
 *  credentials, ranking visibility, and account deletion. */
export default async function SettingsPage() {
  const supabase = await createClient();
  const { data } = await supabase.auth.getClaims();
  const claims = data?.claims;

  if (!isSignedInViewer(claims)) return <SignedOutSettings />;
  if (!canViewProfile(claims)) return <GuestSettings />;

  const [{ data: profile }, { data: userData }] = await Promise.all([
    supabase.from("profiles").select("display_name, avatar_url, rankings_visible").eq("id", claims.sub).single(),
    // The only place in the app that needs provider identity rather than just
    // claims — getClaims() doesn't carry it, so this one call is a deliberate,
    // scoped exception to the getClaims()-only convention used everywhere else.
    supabase.auth.getUser(),
  ]);

  const displayName = profile?.display_name ?? (claims.email as string | undefined) ?? "Player";
  const email = (claims.email as string | undefined) ?? "";
  const avatarUrl = profile?.avatar_url ?? null;
  const providers = [...new Set((userData?.user?.identities ?? []).map((identity) => identity.provider))];

  return (
    <>
      <Sidebar displayName={displayName} email={email} avatarUrl={avatarUrl} />
      <DashboardHeader displayName={displayName} email={email} avatarUrl={avatarUrl} />
      <main className="app-page flex-1">
        <div className="mx-auto w-full max-w-[1080px]">
          <PageHeader eyebrow="Settings" title="Your settings" description="Credentials, privacy, and your account." />

          <div className="mt-9 grid max-w-[600px] gap-6">
            <SettingsCard title="Account">
              <AccountCredentials email={email} providers={providers} />
            </SettingsCard>

            <SettingsCard title="Privacy">
              <RankingsVisibilityToggle initialVisible={profile?.rankings_visible ?? true} />
            </SettingsCard>

            <SettingsCard title="Danger zone">
              <DeleteAccountSection />
            </SettingsCard>
          </div>
        </div>
      </main>
    </>
  );
}

function SettingsCard({ title, children }: { title: string; children: React.ReactNode }) {
  return (
    <section aria-label={title} className="rounded-card border border-line bg-surface-raised p-5 shadow-well sm:p-6">
      <h2 className="type-label font-black text-hidden">{title}</h2>
      <div className="mt-5">{children}</div>
    </section>
  );
}

function GuestSettings() {
  return (
    <>
      <Sidebar />
      <DashboardHeader displayName={null} email={null} avatarUrl={null} />
      <main className="app-page flex-1">
        <section className="max-w-xl">
          <p className="type-label text-hidden-text">Settings</p>
          <h1 className="mt-3 font-slab text-[36px] leading-[.96] uppercase sm:text-[46px]">Make it yours</h1>
          <p className="mt-4 text-[15px] leading-6 text-fg-muted">Your name is just for the current game. Create an account to get settings for credentials, privacy, and more.</p>
          <div className="mt-6"><GuestUpgrade /></div>
        </section>
      </main>
    </>
  );
}

function SignedOutSettings() {
  return (
    <>
      <Sidebar />
      <DashboardHeader displayName={null} email={null} avatarUrl={null} />
      <main className="app-page flex-1">
        <section className="max-w-xl">
          <p className="type-label text-hidden-text">Settings</p>
          <h1 className="mt-3 font-slab text-[36px] leading-[.96] uppercase sm:text-[46px]">Sign in for settings</h1>
          <p className="mt-4 text-[15px] leading-6 text-fg-muted">Sign in to manage your credentials and account.</p>
          <Link href="/login?next=/settings" className="mt-6 inline-flex bg-panel px-4 py-3 type-label font-bold text-panel-fg focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-panel">Sign in</Link>
        </section>
      </main>
    </>
  );
}
