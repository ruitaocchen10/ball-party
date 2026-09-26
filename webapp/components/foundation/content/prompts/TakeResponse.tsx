import { PowerRankingsSlot, SlotFaceC, YourCalls } from "./SlotFaces";
import { isPicksPost } from "@/lib/foundation/content/prompts/logic";
import type { Post } from "@/lib/foundation/content/prompts/types";

/**
 * A take's saved answer, read-only, for whichever template the prompt uses —
 * the one place that knows how each kind is drawn. The viewer's own card and
 * everyone else's expandable take share it, so no kind can end up with a
 * result view that only one of them has.
 */
export function TakeResponse({
  post,
  response,
  collapsible = false,
  isViewer = true,
}: {
  post: Post;
  response: Record<string, string[]>;
  /** Large picks slates start compact; it has no effect on other templates. */
  collapsible?: boolean;
  /** Whose answer this is. The viewer's rankings show movement since their last ballot; nobody else's can. */
  isViewer?: boolean;
}) {
  if (isPicksPost(post)) return <YourCalls slots={post.slots} responses={response} collapsible={collapsible} />;

  if (post.templateKind === "power_rankings") {
    return (
      <div className="px-4 pt-4">
        <PowerRankingsSlot
          slot={post.slots[0]}
          disabled
          showEditorHeader={false}
          response={response[post.slots[0].id] ?? []}
          onChange={() => {}}
          showMovement={isViewer}
          previousRankByTeam={post.previousRankByTeam ?? {}}
        />
      </div>
    );
  }

  return (
    <div className="flex flex-col gap-4 px-4 pt-4">
      {post.slots.map((slot) => (
        <SlotFaceC key={slot.id} slot={slot} disabled response={response[slot.id] ?? []} onChange={() => {}} allResponses={response} />
      ))}
    </div>
  );
}
