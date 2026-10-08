"use client";

import { useState } from "react";

import { AuthorAvatar } from "@/components/foundation/content/prompts/AuthorIdentity";
import { Badge } from "@/components/foundation/ui-kit/Badge";
import { Button } from "@/components/foundation/ui-kit/Button";
import { Field, Input } from "@/components/foundation/ui-kit/Input";
import {
  SEND_RESULT_COPY,
  friendErrorMessage,
  parseRelationship,
  parseSendResult,
  type Relationship,
} from "@/lib/foundation/friends/friends";
import { createClient } from "@/lib/supabase/client";

type Found = { profileId: string; username: string; displayName: string; avatarUrl: string | null; relationship: Relationship };

/**
 * Exact-username search. It finds at most one player, so it can't be used to
 * browse accounts. "Not found" and "can't add" read the same on purpose: the
 * server answers both identically so a block or a missing account never shows.
 */
export function PlayerSearch({ onChanged }: { onChanged: () => void | Promise<void> }) {
  const [query, setQuery] = useState("");
  const [searched, setSearched] = useState<string | null>(null);
  const [found, setFound] = useState<Found | null>(null);
  const [message, setMessage] = useState<string | null>(null);
  const [error, setError] = useState<string | null>(null);
  const [busy, setBusy] = useState(false);

  async function search(event: React.FormEvent) {
    event.preventDefault();
    const username = query.trim().replace(/^@/, "");
    if (!username) return;
    setBusy(true);
    setError(null);
    setMessage(null);
    const { data, error: rpcError } = await createClient().rpc("search_users_by_username", { p_query: username });
    setBusy(false);
    if (rpcError) {
      setError(friendErrorMessage(rpcError.message));
      return;
    }
    const row = data?.[0];
    setSearched(username);
    setFound(
      row
        ? {
            profileId: row.profile_id,
            username: row.username,
            displayName: row.display_name,
            avatarUrl: row.avatar_url,
            relationship: parseRelationship(row.relationship),
          }
        : null,
    );
  }

  async function add(target: Found) {
    setBusy(true);
    setError(null);
    const { data, error: rpcError } = await createClient().rpc("send_friend_request", { p_username: target.username });
    setBusy(false);
    if (rpcError) {
      setError(friendErrorMessage(rpcError.message));
      return;
    }
    const result = parseSendResult(data);
    setMessage(SEND_RESULT_COPY[result]);
    if (result === "requested" || result === "already_requested") setFound({ ...target, relationship: "outgoing" });
    if (result === "accepted" || result === "already_friends") setFound({ ...target, relationship: "friends" });
    await onChanged();
  }

  return (
    <div className="rounded-card bg-surface-raised p-4 shadow-well">
      <form onSubmit={search} className="flex flex-col gap-2 sm:flex-row sm:items-end">
        <div className="min-w-0 flex-1">
          <Field label="Find by username">
            <Input
              variant="well"
              value={query}
              onChange={(event) => setQuery(event.target.value)}
              autoCapitalize="none"
              autoCorrect="off"
              spellCheck={false}
              placeholder="their exact username"
              maxLength={21}
            />
          </Field>
        </div>
        <Button type="submit" fullWidth={false} className="sm:min-w-28" disabled={busy || query.trim() === ""}>
          Search
        </Button>
      </form>

      {error ? <p role="alert" className="mt-3 text-sm text-hidden-text">{error}</p> : null}

      {searched !== null && !found && !error ? (
        <p role="status" className="mt-3 text-sm text-fg-muted">
          {message ?? "No player found with that exact username."}
        </p>
      ) : null}

      {found ? (
        <div className="mt-3 flex flex-wrap items-center gap-3 border-t border-line pt-3">
          <AuthorAvatar name={found.displayName} avatarUrl={found.avatarUrl} className="h-9 w-9" />
          <span className="min-w-0 flex-1">
            <span className="block truncate font-medium">{found.displayName}</span>
            <span className="block truncate type-label-xs text-fg-muted">@{found.username}</span>
          </span>
          <FoundAction found={found} busy={busy} onAdd={() => add(found)} />
          {message ? <p role="status" className="w-full text-sm text-fg-muted">{message}</p> : null}
        </div>
      ) : null}
    </div>
  );
}

function FoundAction({ found, busy, onAdd }: { found: Found; busy: boolean; onAdd: () => void }) {
  switch (found.relationship) {
    case "friends":
      return <Badge tone="success">Friends</Badge>;
    case "outgoing":
      return <Badge tone="muted">Requested</Badge>;
    case "blocked":
      return <Badge tone="muted">Blocked</Badge>;
    case "incoming":
      // They already asked us; asking back means yes (the server accepts).
      return (
        <Button size="sm" fullWidth={false} disabled={busy} onClick={onAdd}>
          Accept request
        </Button>
      );
    default:
      return (
        <Button size="sm" fullWidth={false} disabled={busy} onClick={onAdd}>
          Add friend
        </Button>
      );
  }
}
