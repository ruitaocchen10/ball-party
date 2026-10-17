"use client";

import { useRouter } from "next/navigation";
import { useState } from "react";

import { Button } from "@/components/foundation/ui-kit/Button";
import type { AdminAction } from "@/lib/foundation/moderation/reports";
import { createClient } from "@/lib/supabase/client";

/** Dismiss a report, remove the reported take, or ban the player. The RPC enforces that only the admin can. */
export function ReportActions({ reportId, kind }: { reportId: string; kind: "take" | "profile" }) {
  const router = useRouter();
  const [pending, setPending] = useState(false);
  const [error, setError] = useState<string | null>(null);

  async function run(action: AdminAction) {
    if (action === "ban" && !window.confirm("Ban this player and remove all of their takes?")) return;
    setPending(true);
    setError(null);
    const { error: rpcError } = await createClient().rpc("admin_resolve_report", { p_report_id: reportId, p_action: action });
    setPending(false);
    if (rpcError) setError(rpcError.message);
    else router.refresh();
  }

  return (
    <div className="flex flex-col items-end gap-1">
      <div className="flex flex-wrap justify-end gap-2">
        <Button size="sm" variant="ghost" fullWidth={false} disabled={pending} onClick={() => run("dismiss")}>Dismiss</Button>
        {kind === "take" ? (
          <Button size="sm" variant="ink" fullWidth={false} disabled={pending} onClick={() => run("remove")}>Remove take</Button>
        ) : null}
        <Button size="sm" variant="danger" fullWidth={false} disabled={pending} onClick={() => run("ban")}>Ban player</Button>
      </div>
      {error ? <p role="alert" className="text-sm text-hidden-text">{error}</p> : null}
    </div>
  );
}
