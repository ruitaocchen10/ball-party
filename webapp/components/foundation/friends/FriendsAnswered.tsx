import { AuthorAvatar } from "@/components/foundation/content/prompts/AuthorIdentity";
import { friendsAnsweredLine, type FriendAnswerer } from "@/lib/foundation/friends/friends";

/** A prompt card's social line: which friends answered, as stacked avatars and names. Never their picks. With `total` it also folds in everyone else who answered. */
export function FriendsAnswered({ answerers, total }: { answerers: FriendAnswerer[]; total?: number }) {
  const line = friendsAnsweredLine(answerers, total);
  if (!line) return null;
  return (
    <p className="flex items-center gap-2 text-[13px] leading-5 text-fg-muted">
      <span aria-hidden className="flex -space-x-2">
        {answerers.slice(0, 3).map((answerer) => (
          <AuthorAvatar key={answerer.actorId} name={answerer.displayName} avatarUrl={answerer.avatarUrl} className="h-6 w-6 ring-2 ring-surface-raised" />
        ))}
      </span>
      <span className="min-w-0 truncate">{line}</span>
    </p>
  );
}
