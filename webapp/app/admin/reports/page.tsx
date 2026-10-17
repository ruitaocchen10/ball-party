import { ReportActions } from "@/components/admin/ReportActions";
import { EmptyState } from "@/components/foundation/ui-kit/EmptyState";
import { reasonLabel, type AdminReport } from "@/lib/foundation/moderation/reports";
import { createClient } from "@/lib/supabase/server";

/**
 * Reports on takes and profiles, oldest first (0220). The layout has already
 * checked the viewer is the admin; `admin_list_reports` checks again.
 */
export default async function AdminReportsPage() {
  const supabase = await createClient();
  const { data, error } = await supabase.rpc("admin_list_reports", { p_status: "open" });
  const reports: AdminReport[] = (data ?? []).map((row) => ({
    id: row.id,
    kind: row.kind === "profile" ? "profile" : "take",
    reason: row.reason,
    details: row.details,
    createdAt: row.created_at,
    reporterName: row.reporter_name,
    targetUserId: row.target_user_id,
    targetName: row.target_name,
    targetUsername: row.target_username,
    commentBody: row.comment_body,
    postId: row.post_id,
    targetReportCount: Number(row.target_report_count),
  }));

  return (
    <div className="mx-auto w-full max-w-5xl px-4 pt-8 pb-16 sm:px-6">
      <h1 className="font-slab text-2xl leading-none uppercase">Reports</h1>
      <p className="mt-2 max-w-[60ch] text-sm text-fg-muted">
        Open reports from players, oldest first. Removing a take hides it from everyone; banning a player removes all of their takes and stops them signing in.
      </p>

      {error ? (
        <EmptyState title="Couldn't load reports" className="mt-8">{error.message}</EmptyState>
      ) : reports.length === 0 ? (
        <EmptyState title="No open reports" className="mt-8">Nothing to review.</EmptyState>
      ) : (
        <ul className="mt-6 flex flex-col gap-3">
          {reports.map((report) => (
            <li key={report.id} className="flex flex-col gap-3 rounded-card border border-line bg-surface-raised p-4 sm:flex-row sm:items-start">
              <div className="min-w-0 flex-1">
                <p className="type-label text-fg-muted">
                  {report.kind === "take" ? "Take" : "Profile"} · {reasonLabel(report.reason)} · {new Date(report.createdAt).toLocaleString()}
                </p>
                <p className="mt-1 font-medium">
                  {report.targetName}
                  {report.targetUsername ? <span className="text-fg-muted"> @{report.targetUsername}</span> : null}
                  <span className="text-fg-muted"> · {report.targetReportCount} report{report.targetReportCount === 1 ? "" : "s"} in total</span>
                </p>
                {report.commentBody ? <p className="mt-2 text-sm leading-6">&ldquo;{report.commentBody}&rdquo;</p> : null}
                {report.details ? <p className="mt-2 text-sm text-fg-muted">{report.reporterName} says: {report.details}</p> : <p className="mt-2 text-xs text-fg-muted">Reported by {report.reporterName}</p>}
              </div>
              <ReportActions reportId={report.id} kind={report.kind} />
            </li>
          ))}
        </ul>
      )}
    </div>
  );
}
