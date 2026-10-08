import type { Metadata } from "next";
import Link from "next/link";

import { FriendInviteCard } from "@/components/foundation/friends/FriendInviteCard";
import { DashboardHeader } from "@/components/home/DashboardHeader";
import { ButtonLink } from "@/components/foundation/ui-kit/Button";
import { PageShell } from "@/components/foundation/ui-kit/PageShell";
import { Sidebar } from "@/components/foundation/ui-kit/Sidebar";
import { friendInvitePath, parseRelationship } from "@/lib/foundation/friends/friends";
import { canViewProfile, chromeIdentity, isSignedInViewer } from "@/lib/foundation/identity/viewer";
import { createClient } from "@/lib/supabase/server";

export const metadata: Metadata = { title: "Friend invite", robots: { index: false } };

/**
 * Where an invite link lands. The proxy sends signed-out visitors through
 * /login?next=<this path> and back. A guest is asked to create an account
 * first. An unknown code, your own code, and a code whose owner blocked you
 * all show the same "isn't available" page.
 */
export default async function FriendInvitePage(props: PageProps<"/friends/invite/[code]">) {
  const { code } = await props.params;
  const supabase = await createClient();
  const { data } = await supabase.auth.getClaims();
  const claims = data?.claims;

  if (!isSignedInViewer(claims) || !canViewProfile(claims)) {
    return (
      <Shell>
        <Notice
          eyebrow="Friend invite"
          title="Create an account to accept"
          body="Friends need a real account. Create one, then come back to this link."
          action={<ButtonLink href={`/signup?next=${encodeURIComponent(friendInvitePath(code))}`}>Create an account</ButtonLink>}
        />
      </Shell>
    );
  }

  const [{ data: profile }, lookup] = await Promise.all([
    supabase.from("profiles").select("display_name, avatar_url").eq("id", claims.sub).single(),
    supabase.rpc("lookup_friend_code", { p_code: code }),
  ]);
  const chrome = chromeIdentity(claims, profile);
  const owner = lookup.data?.[0];

  return (
    <Shell chrome={chrome}>
      {owner && owner.username ? (
        <FriendInviteCard
          code={code}
          owner={{
            username: owner.username,
            displayName: owner.display_name,
            avatarUrl: owner.avatar_url,
            relationship: parseRelationship(owner.relationship),
          }}
        />
      ) : (
        <Notice
          eyebrow="Friend invite"
          title="Invite isn't available"
          body="This link may have expired, been reset, or be your own. Ask your friend for a fresh one."
          action={<ButtonLink href="/profile?tab=friends" variant="ghost">Go to friends</ButtonLink>}
        />
      )}
    </Shell>
  );
}

function Shell({
  chrome,
  children,
}: {
  chrome?: { displayName: string | null; email: string | null; avatarUrl: string | null };
  children: React.ReactNode;
}) {
  return (
    <>
      <Sidebar displayName={chrome?.displayName} email={chrome?.email} avatarUrl={chrome?.avatarUrl} />
      <DashboardHeader
        displayName={chrome?.displayName ?? null}
        email={chrome?.email ?? null}
        avatarUrl={chrome?.avatarUrl ?? null}
      />
      <PageShell variant="dashboard">
        <div className="mx-auto w-full max-w-lg pt-6">{children}</div>
      </PageShell>
    </>
  );
}

function Notice({
  eyebrow,
  title,
  body,
  action,
}: {
  eyebrow: string;
  title: string;
  body: string;
  action: React.ReactNode;
}) {
  return (
    <section className="rounded-card bg-surface-raised p-6 text-center shadow-well">
      <p className="type-label text-hidden-text">{eyebrow}</p>
      <h1 className="mt-2 font-slab text-[34px] leading-none uppercase">{title}</h1>
      <p className="mx-auto mt-3 max-w-sm text-[15px] leading-6 text-fg-muted">{body}</p>
      <div className="mx-auto mt-6 max-w-xs">{action}</div>
      <Link href="/" className="mt-4 inline-block type-label text-fg-muted underline underline-offset-2 hover:text-fg">
        Back home
      </Link>
    </section>
  );
}
