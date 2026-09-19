import type { Metadata } from "next";
import { notFound } from "next/navigation";
import type { ReactNode } from "react";

import { AdminNav } from "@/components/admin/AdminNav";
import { isAdminViewer } from "@/lib/foundation/identity/viewer";
import { createClient } from "@/lib/supabase/server";

export const metadata: Metadata = { title: "Admin", robots: { index: false, follow: false } };

/**
 * Shell for every /admin/* route — nav plus the one place the admin-only
 * gate lives, so an individual page under here never has to repeat it.
 *
 * A signed-out visitor never reaches this layout at all: /admin isn't in
 * proxy.ts's PUBLIC_PATHS, so the existing middleware already redirects them
 * to /login with the exact path they asked for. What only this layout can
 * check is *which* signed-in account this is — isAdminViewer treats missing
 * claims the same as a non-admin account, so both cases just fall through to
 * the same notFound(). A 404 rather than a "you're not allowed" page, so the
 * route doesn't confirm to a curious signed-in stranger that it exists.
 *
 * No Sidebar here — this isn't part of the consumer app's chrome.
 */
export default async function AdminLayout({ children }: { children: ReactNode }) {
  const supabase = await createClient();
  const { data } = await supabase.auth.getClaims();

  if (!isAdminViewer(data?.claims)) {
    notFound();
  }

  return (
    <div className="min-h-dvh">
      <AdminNav />
      {/* Each page manages its own padding/max-width — PromptPostComposer already
          did before this layout existed, and the placeholder sections match it
          so nothing looks inconsistent side by side. */}
      <main>{children}</main>
    </div>
  );
}
