import Link from "next/link";

import { PostActions, type AdminSlot } from "@/components/admin/PostActions";
import { createClient } from "@/lib/supabase/server";

const FILTERS = ["all", "open", "locked", "resolved", "void"] as const;
type Filter = (typeof FILTERS)[number];

const STATUS_LABELS: Record<Exclude<Filter, "all">, string> = {
  open: "Open",
  locked: "Locked",
  resolved: "Resolved",
  void: "Void",
};

function selectedFilter(status: string | undefined): Filter {
  return FILTERS.includes(status as Filter) ? (status as Filter) : "open";
}

/** Read once per request — this page is server-rendered on every visit. */
function hasLocked(lockAt: string) {
  return new Date(lockAt).getTime() <= Date.now();
}

function formatDate(value: string) {
  return new Intl.DateTimeFormat("en-US", {
    month: "short",
    day: "numeric",
    year: "numeric",
    hour: "numeric",
    minute: "2-digit",
  }).format(new Date(value));
}

/**
 * The admin's prompt index. It opens on the open-status slice, while the
 * other lifecycle filters keep finished and voided posts discoverable too.
 * Open and locked posts carry resolve/void controls; game picks with a
 * resolution source are graded by auto_resolve_tick (0096), so for those
 * Resolve is only the fallback if the sweep can't. Opinion posts (0111) are
 * never graded, so they only get Void. Every post, whatever its status,
 * can be deleted.
 */
export default async function AdminPostsPage({
  searchParams,
}: {
  searchParams: Promise<{ status?: string }>;
}) {
  const { status } = await searchParams;
  const filter = selectedFilter(status);
  const supabase = await createClient();

  let query = supabase
    .from("prompt_posts")
    .select(
      "id, template_kind, is_opinion, template_name, caption, prompt_text, lock_at, status, created_at, resolved_at, void_reason, resolution_source, prompt_slots(id, label, shape, pick_count, sort_order, prompt_slot_options(id, label, sublabel, sort_order))",
    )
    .order("created_at", { ascending: false });

  if (filter !== "all") query = query.eq("status", filter);

  const { data: posts, error } = await query;

  return (
    <div className="mx-auto w-full max-w-5xl px-4 pt-8 pb-16 sm:px-6">
      <h1 className="font-slab text-2xl leading-none uppercase">Posts</h1>
      <p className="mt-2 max-w-[60ch] text-sm text-fg-muted">
        Every prompt post, organized by its lifecycle. The lock time shows when answers close.
      </p>

      <nav aria-label="Filter posts by status" className="mt-7 flex flex-wrap gap-2">
        {FILTERS.map((candidate) => {
          const active = filter === candidate;
          const href = candidate === "open" ? "/admin/posts" : `/admin/posts?status=${candidate}`;
          return (
            <Link
              key={candidate}
              href={href}
              aria-current={active ? "page" : undefined}
              className={`border px-3 py-2 font-mono text-[10px] font-bold tracking-[0.12em] uppercase transition-colors ${
                active ? "border-fg bg-fg text-surface" : "border-line text-fg-muted hover:border-fg hover:text-fg"
              }`}
            >
              {candidate === "all" ? "All" : STATUS_LABELS[candidate]}
            </Link>
          );
        })}
      </nav>

      {error ? (
        <p className="mt-8 text-sm text-fg-muted">Posts could not be loaded. Please try again.</p>
      ) : posts?.length ? (
        <ul className="mt-6 divide-y divide-line border-y border-line">
          {posts.map((post) => {
            const slots: AdminSlot[] = [...post.prompt_slots]
              .sort((a, b) => a.sort_order - b.sort_order)
              .map((slot) => ({
                id: slot.id,
                label: slot.label,
                shape: slot.shape,
                pickCount: slot.pick_count,
                options: [...slot.prompt_slot_options]
                  .sort((a, b) => a.sort_order - b.sort_order)
                  .map(({ id, label, sublabel }) => ({ id, label, sublabel })),
              }));
            const actionable = post.status === "open" || post.status === "locked";
            const autoResolves = ["picks", "game_pick", "weekly_picks"].includes(post.template_kind) && post.resolution_source !== null;
            return (
            <li key={post.id} className="grid gap-3 py-4 sm:grid-cols-[minmax(0,1fr)_auto] sm:items-start sm:gap-6">
              <div className="min-w-0">
                <p className="type-label text-fg-muted">{post.template_name}</p>
                <h2 className="mt-1 truncate text-base font-semibold text-fg">{post.caption || post.prompt_text}</h2>
                {post.caption ? <p className="mt-1 line-clamp-2 text-sm text-fg-muted">{post.prompt_text}</p> : null}
              </div>
              <div className="flex shrink-0 items-center gap-3 sm:flex-col sm:items-end sm:gap-1">
                <span className="border border-line px-2 py-1 type-label font-bold text-fg">
                  {STATUS_LABELS[post.status as Exclude<Filter, "all">] ?? post.status}
                </span>
                <p className="font-mono text-[10px] tracking-[0.04em] text-fg-muted">
                  {post.status === "resolved" && post.resolved_at ? `Resolved ${formatDate(post.resolved_at)}` : `Locks ${formatDate(post.lock_at)}`}
                </p>
              </div>
              {post.status === "void" && post.void_reason ? <p className="text-sm text-fg-muted sm:col-span-2">Void reason: {post.void_reason}</p> : null}
              {actionable && autoResolves ? (
                <p className="text-sm text-fg-muted sm:col-span-2">Grades automatically once the game is final.</p>
              ) : null}
              {actionable && post.is_opinion ? (
                <p className="text-sm text-fg-muted sm:col-span-2">Opinion post — there&apos;s no right answer to grade, so it can only be voided.</p>
              ) : null}
              <PostActions
                postId={post.id}
                slots={slots}
                canResolve={!post.is_opinion && hasLocked(post.lock_at)}
                canClose={actionable}
              />
            </li>
            );
          })}
        </ul>
      ) : (
        <p className="mt-8 text-sm text-fg-muted">No {filter === "all" ? "posts" : `${STATUS_LABELS[filter].toLowerCase()} posts`} yet.</p>
      )}
    </div>
  );
}
