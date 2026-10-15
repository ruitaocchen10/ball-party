import type { ReactNode } from "react";

import { DashboardHeader } from "@/components/home/DashboardHeader";
import { PageShell } from "@/components/foundation/ui-kit/PageShell";
import { Sidebar } from "@/components/foundation/ui-kit/Sidebar";
import type { ChromeIdentity } from "@/lib/foundation/identity/viewer";

/** The dashboard frame every Lists page shares: sidebar, top bar and the page column. */
export function ListsChrome({ chrome, children, rail }: { chrome: ChromeIdentity; children: ReactNode; rail?: ReactNode }) {
  return (
    <>
      <Sidebar displayName={chrome.displayName} email={chrome.email} avatarUrl={chrome.avatarUrl} />
      <DashboardHeader displayName={chrome.displayName} email={chrome.email} avatarUrl={chrome.avatarUrl} />
      <PageShell variant="dashboard" rail={rail}>{children}</PageShell>
    </>
  );
}
