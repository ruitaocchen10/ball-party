import { OptionIcon, PowerRankingsSlot, SlotFaceC, YourCalls } from "./SlotFaces";
import { WeeklyAwardsBallot } from "./WeeklyAwards";
import { isPicksPost } from "@/lib/foundation/content/prompts/logic";
import type { Post } from "@/lib/foundation/content/prompts/types";

/** How many of the crowd's top-five teams a ballot also has in its own top five. */
export function crowdTopFiveMatches(crowd: string[], ballot: string[]): number {
  const mine = new Set(ballot.slice(0, 5));
  return crowd.filter((id) => mine.has(id)).length;
}

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

  if (post.templateKind === "weekly_awards") return <WeeklyAwardsBallot post={post} response={response} />;

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
        <CrowdTopFive post={post} ballot={response[post.slots[0].id] ?? []} />
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

/** Under a power rankings ballot: the crowd's top five as small marks, dimmed where the ballot left that team out of its top five, and how many it matched. */
function CrowdTopFive({ post, ballot }: { post: Post; ballot: string[] }) {
  const slot = post.slots[0];
  const crowd = (post.powerRankingTopFive ?? []).flatMap((entry) => slot.options.find((option) => option.id === entry.optionId) ?? []);
  if (!crowd.length) return null;
  const mine = new Set(ballot.slice(0, 5));
  const matched = crowdTopFiveMatches(crowd.map((option) => option.id), ballot);
  return (
    <div className="mt-3 flex items-center gap-2 border-t border-line pt-3" aria-label={`The crowd's top five: ${crowd.map((option) => option.label).join(", ")}. This ballot matched ${matched} of ${crowd.length}.`}>
      <span className="type-label text-fg-muted">Crowd&apos;s top 5</span>
      <span className="ml-auto flex items-center gap-1.5" aria-hidden>
        {crowd.map((option) => (
          <span key={option.id} className={mine.has(option.id) ? "" : "opacity-35"}>
            <OptionIcon option={option} className="h-6 w-6" />
          </span>
        ))}
      </span>
      <span className="type-label text-fg-muted" aria-hidden>
        matched {matched} of {crowd.length}
      </span>
    </div>
  );
}
