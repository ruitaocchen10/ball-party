"use client";

import { Bell } from "lucide-react";
import Link from "next/link";
import { useRouter } from "next/navigation";
import { useCallback, useEffect, useId, useRef, useState } from "react";

import { AuthorAvatar } from "@/components/foundation/content/prompts/AuthorIdentity";
import { Button } from "@/components/foundation/ui-kit/Button";
import { EmptyState } from "@/components/foundation/ui-kit/EmptyState";
import { friendErrorMessage } from "@/lib/foundation/friends/friends";
import {
  badgeLabel,
  inboxDetail,
  inboxHasActions,
  inboxHref,
  inboxTitle,
  toInboxItems,
  type InboxItem,
} from "@/lib/foundation/notifications/inbox";
import { inviteErrorMessage } from "@/lib/platform/lobbies/invites";
import { createRealtimeClient } from "@/lib/runtime/realtime/client";
import { createClient } from "@/lib/supabase/client";

const FOCUS = "focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-fg";

/**
 * The notification bell and its inbox. The server decides which items exist
 * and what state each is in (`list_inbox`); this only lists them, runs the
 * accept / decline actions the server already exposes, and re-reads.
 *
 * Opening the panel does not mark everything read. An item is read when it is
 * tapped or acted on, or all at once with "Mark all read", so a glance at the
 * list doesn't make a friend request look handled. Room invites carry no read
 * state: they count as unread while they can still be answered.
 *
 * Changes to the viewer's own `notifications` and `room_invites` rows are only
 * a nudge to re-read, the same as the Party page's invites.
 */
export function NotificationBell() {
  const router = useRouter();
  const [viewerId, setViewerId] = useState<string | null>(null);
  const [items, setItems] = useState<InboxItem[]>([]);
  const [unread, setUnread] = useState(0);
  const [open, setOpen] = useState(false);
  const [busy, setBusy] = useState<string | null>(null);
  const [errors, setErrors] = useState<Record<string, string>>({});
  const root = useRef<HTMLDivElement>(null);

  const refetch = useCallback(async () => {
    const supabase = createClient();
    const [list, count] = await Promise.all([supabase.rpc("list_inbox"), supabase.rpc("inbox_unread_count")]);
    // A failed read keeps whatever is shown; the next event or reconnect retries.
    if (list.error || !list.data) return;
    setItems(toInboxItems(list.data));
    if (!count.error && typeof count.data === "number") setUnread(count.data);
  }, []);

  useEffect(() => {
    let cancelled = false;
    void createClient()
      .auth.getUser()
      .then(({ data }) => {
        if (!cancelled) setViewerId(data.user?.id ?? null);
      });
    return () => {
      cancelled = true;
    };
  }, []);

  // The bell is mounted twice on a page (the desktop header and the mobile top bar), on one
  // shared Realtime client. A channel name is a key there: a second `.channel()` with the same
  // name hands back the first, already-subscribed channel and `.on()` on it throws. So each
  // instance gets its own name (and its own cleanup, rather than closing the other's).
  const instanceId = useId().replace(/\W/g, "");

  useEffect(() => {
    if (!viewerId) return;
    let cancelled = false;
    let cleanup: (() => void) | null = null;

    void (async () => {
      const supabase = await createRealtimeClient();
      if (cancelled) return;
      // Read now rather than waiting for the socket to join: the badge shouldn't depend on it.
      void refetch();
      const channel = supabase
        .channel(`inbox:${viewerId}:${instanceId}`)
        .on(
          "postgres_changes",
          { event: "*", schema: "public", table: "notifications", filter: `recipient_id=eq.${viewerId}` },
          () => void refetch(),
        )
        .on(
          "postgres_changes",
          { event: "*", schema: "public", table: "room_invites", filter: `recipient_id=eq.${viewerId}` },
          () => void refetch(),
        )
        // First connect and every resubscribe: anything that arrived while the socket was down produced no event.
        .subscribe((status) => {
          if (status === "SUBSCRIBED") void refetch();
        });
      cleanup = () => void supabase.removeChannel(channel);
    })();

    return () => {
      cancelled = true;
      cleanup?.();
    };
  }, [viewerId, refetch, instanceId]);

  useEffect(() => {
    if (!open) return;
    function onKeyDown(event: KeyboardEvent) {
      if (event.key === "Escape") setOpen(false);
    }
    function onPointerDown(event: PointerEvent) {
      if (root.current && !root.current.contains(event.target as Node)) setOpen(false);
    }
    document.addEventListener("keydown", onKeyDown);
    document.addEventListener("pointerdown", onPointerDown);
    return () => {
      document.removeEventListener("keydown", onKeyDown);
      document.removeEventListener("pointerdown", onPointerDown);
    };
  }, [open]);

  const markRead = useCallback(
    async (item: InboxItem) => {
      if (!item.key.startsWith("n:") || !item.isUnread) return;
      await createClient().rpc("mark_notification_read", { p_item_key: item.key });
      await refetch();
    },
    [refetch],
  );

  async function run(item: InboxItem, call: () => Promise<{ error: { message: string } | null }>, after?: () => void) {
    setBusy(item.key);
    setErrors((prev) => ({ ...prev, [item.key]: "" }));
    const { error } = await call();
    setBusy(null);
    if (error) {
      const message = item.kind === "room_invite" ? inviteErrorMessage(error.message) : friendErrorMessage(error.message);
      setErrors((prev) => ({ ...prev, [item.key]: message }));
      // A dead item will never work: re-read so the server's state replaces it.
      await refetch();
      return;
    }
    after?.();
    await markRead(item);
    await refetch();
  }

  function accept(item: InboxItem) {
    const supabase = createClient();
    if (item.kind === "friend_request") {
      return run(item, async () => await supabase.rpc("accept_friend_request", { p_user_id: item.actorId }));
    }
    return run(item, async () => {
      const { data, error } = await supabase.rpc("accept_room_invite", { p_invite_id: item.refId });
      if (!error && data) {
        setOpen(false);
        router.push(`/lobby/${data.code}`);
      }
      return { error };
    });
  }

  function decline(item: InboxItem) {
    const supabase = createClient();
    if (item.kind === "friend_request") {
      return run(item, async () => await supabase.rpc("decline_friend_request", { p_user_id: item.actorId }));
    }
    return run(item, async () => await supabase.rpc("decline_room_invite", { p_invite_id: item.refId }));
  }

  async function markAllRead() {
    await createClient().rpc("mark_all_notifications_read");
    await refetch();
  }

  if (!viewerId) return null;

  const badge = badgeLabel(unread);

  return (
    <div ref={root} className="relative">
      <button
        type="button"
        onClick={() => setOpen((value) => !value)}
        aria-label={unread > 0 ? `Notifications, ${unread} new` : "Notifications"}
        aria-expanded={open}
        aria-haspopup="dialog"
        className={`relative flex h-10 w-10 items-center justify-center text-fg-muted transition-colors hover:text-fg ${FOCUS}`}
      >
        <Bell aria-hidden className="h-[18px] w-[18px]" strokeWidth={1.6} />
        {badge ? (
          <span
            aria-hidden
            className="absolute top-1 right-0.5 flex min-w-4 items-center justify-center rounded-full bg-hidden-text px-1 type-label-xs font-bold text-panel-fg"
          >
            {badge}
          </span>
        ) : null}
      </button>

      {open ? (
        <div
          role="dialog"
          aria-label="Notifications"
          className="fixed inset-x-3 top-[72px] z-40 max-h-[70dvh] overflow-y-auto rounded-card bg-panel text-panel-fg shadow-card ring-1 ring-panel-line ring-inset md:absolute md:inset-x-auto md:top-full md:right-0 md:mt-2 md:w-[380px]"
        >
          <div className="flex items-center justify-between border-b border-panel-line px-4 py-3">
            <h2 className="font-slab text-xl uppercase">Notifications</h2>
            {unread > 0 ? (
              <Button variant="text" size="sm" fullWidth={false} onClick={() => void markAllRead()}>
                Mark all read
              </Button>
            ) : null}
          </div>

          {items.length === 0 ? (
            <div className="p-4">
              <EmptyState title="You're all caught up">Friend requests, replies to your takes and room invites show up here.</EmptyState>
            </div>
          ) : (
            <ul>
              {items.map((item) => (
                <li key={item.key} className="border-b border-panel-line last:border-b-0">
                  <ItemRow
                    item={item}
                    busy={busy === item.key}
                    error={errors[item.key] ?? ""}
                    onOpen={() => {
                      setOpen(false);
                      void markRead(item);
                    }}
                    onAccept={() => void accept(item)}
                    onDecline={() => void decline(item)}
                  />
                </li>
              ))}
            </ul>
          )}
        </div>
      ) : null}
    </div>
  );
}

function ItemRow({
  item,
  busy,
  error,
  onOpen,
  onAccept,
  onDecline,
}: {
  item: InboxItem;
  busy: boolean;
  error: string;
  onOpen: () => void;
  onAccept: () => void;
  onDecline: () => void;
}) {
  const href = inboxHref(item);
  const detail = inboxDetail(item);
  const muted = item.state === "expired" || item.state === "declined";
  const body = (
    <>
      <AuthorAvatar name={item.actorName} avatarUrl={item.actorAvatarUrl} className="h-9 w-9" />
      <span className="min-w-0 flex-1">
        <span className={`block text-sm font-medium ${muted ? "text-panel-muted" : ""}`}>{inboxTitle(item)}</span>
        {detail ? <span className="block type-label-xs text-panel-muted">{detail}</span> : null}
      </span>
      {item.isUnread ? <span aria-label="Unread" className="h-2 w-2 shrink-0 rounded-full bg-hidden-text" /> : null}
    </>
  );

  return (
    <div className="px-4 py-3">
      {href ? (
        <Link href={href} onClick={onOpen} className={`flex items-center gap-3 ${FOCUS}`}>
          {body}
        </Link>
      ) : (
        <div className="flex items-center gap-3">{body}</div>
      )}
      {inboxHasActions(item) ? (
        <div className="mt-2 flex gap-2 pl-12">
          <Button variant="ink" size="sm" fullWidth={false} disabled={busy} onClick={onAccept}>
            {item.kind === "room_invite" ? "Join" : "Accept"}
          </Button>
          <Button variant="ghost" size="sm" fullWidth={false} disabled={busy} onClick={onDecline}>
            Decline
          </Button>
        </div>
      ) : null}
      {error ? (
        <p role="alert" className="mt-1 pl-12 text-xs text-hidden-ink">
          {error}
        </p>
      ) : null}
    </div>
  );
}
