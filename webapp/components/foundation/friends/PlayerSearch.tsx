"use client";

import { useEffect, useState } from "react";

import { AuthorAvatar } from "@/components/foundation/content/prompts/AuthorIdentity";
import { Badge } from "@/components/foundation/ui-kit/Badge";
import { Button } from "@/components/foundation/ui-kit/Button";
import { Field, Input } from "@/components/foundation/ui-kit/Input";
import { usernameFormatHint } from "@/lib/foundation/identity/username";
import {
  SEND_RESULT_COPY,
  friendErrorMessage,
  parseRelationship,
  parseSendResult,
  type Relationship,
} from "@/lib/foundation/friends/friends";
import { createClient } from "@/lib/supabase/client";

type Found = { profileId: string; username: string; displayName: string; avatarUrl: string | null; relationship: Relationship };

const DEBOUNCE_MS = 250;

/** The last answer from the server, tagged with the query it was for. */
type Answer = { query: string; hits: Found[]; error: string | null };

/**
 * Username typeahead: players whose username starts with what you've typed
 * appear in a dropdown. The server asks for at least 3 characters and returns
 * a handful, so it still can't be used to browse accounts. "Not found" and
 * "can't add" read the same on purpose: the server answers both identically so
 * a block or a missing account never shows.
 */
export function PlayerSearch({ onChanged }: { onChanged: () => void | Promise<void> }) {
  const [query, setQuery] = useState("");
  const [answer, setAnswer] = useState<Answer | null>(null);
  const [message, setMessage] = useState<string | null>(null);
  const [error, setError] = useState<string | null>(null);
  const [busy, setBusy] = useState(false);
  const [dismissed, setDismissed] = useState<string | null>(null);

  const trimmed = query.trim().replace(/^@/, "");
  const shouldSearch = usernameFormatHint(trimmed) === null;

  // Only the debounced callback sets state, so nothing is set from the effect body.
  useEffect(() => {
    if (!shouldSearch) return;
    let cancelled = false;
    const timer = setTimeout(async () => {
      const { data, error: rpcError } = await createClient().rpc("search_users_by_username", { p_query: trimmed });
      if (cancelled) return;
      setAnswer({
        query: trimmed,
        error: rpcError ? friendErrorMessage(rpcError.message) : null,
        hits: (data ?? []).map((row) => ({
          profileId: row.profile_id,
          username: row.username,
          displayName: row.display_name,
          avatarUrl: row.avatar_url,
          relationship: parseRelationship(row.relationship),
        })),
      });
    }, DEBOUNCE_MS);
    return () => {
      cancelled = true;
      clearTimeout(timer);
    };
  }, [trimmed, shouldSearch]);

  const current = shouldSearch && answer?.query === trimmed ? answer : null;
  const open = current !== null && dismissed !== trimmed;

  function update(target: Found, relationship: Relationship) {
    setAnswer((prev) =>
      prev ? { ...prev, hits: prev.hits.map((hit) => (hit.profileId === target.profileId ? { ...hit, relationship } : hit)) } : prev,
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
    if (result === "requested" || result === "already_requested") update(target, "outgoing");
    if (result === "accepted" || result === "already_friends") update(target, "friends");
    await onChanged();
  }

  return (
    <div className="rounded-card bg-surface-raised p-4 shadow-well">
      <div className="relative">
        <Field label="Find by username">
          <Input
            variant="well"
            value={query}
            onChange={(event) => {
              setQuery(event.target.value);
              setMessage(null);
              setError(null);
            }}
            onKeyDown={(event) => {
              if (event.key === "Escape") setDismissed(trimmed);
            }}
            onFocus={() => setDismissed(null)}
            autoCapitalize="none"
            autoCorrect="off"
            autoComplete="off"
            spellCheck={false}
            placeholder="start typing a username"
            maxLength={21}
          />
        </Field>

        {open ? (
          <div className="absolute inset-x-0 top-full z-10 mt-1 overflow-hidden rounded-card bg-surface-raised shadow-well ring-1 ring-line">
            {current.error ? (
              <p role="alert" className="p-3 text-sm text-hidden-text">{current.error}</p>
            ) : current.hits.length === 0 ? (
              <p role="status" className="p-3 text-sm text-fg-muted">No players found.</p>
            ) : (
              <ul aria-label="Matching players" className="divide-y divide-line">
                {current.hits.map((hit) => (
                  <li key={hit.profileId} className="flex items-center gap-3 p-3">
                    <AuthorAvatar name={hit.displayName} avatarUrl={hit.avatarUrl} className="h-9 w-9" />
                    <span className="min-w-0 flex-1">
                      <span className="block truncate font-medium">{hit.displayName}</span>
                      <span className="block truncate type-label-xs text-fg-muted">@{hit.username}</span>
                    </span>
                    <FoundAction found={hit} busy={busy} onAdd={() => add(hit)} />
                  </li>
                ))}
              </ul>
            )}
          </div>
        ) : null}
      </div>

      {error ? <p role="alert" className="mt-3 text-sm text-hidden-text">{error}</p> : null}
      {message ? <p role="status" className="mt-3 text-sm text-fg-muted">{message}</p> : null}
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
