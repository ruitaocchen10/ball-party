import { OptionIcon } from "./SlotFaces";
import { isPicksPost, relativeTime } from "@/lib/foundation/content/prompts/logic";
import type { Post } from "@/lib/foundation/content/prompts/types";

/**
 * The detail page's right rail. Used to duplicate OtherTakes as a second,
 * differently-styled list of the same takes now shown in the thread; carries
 * prompt context instead — what it takes to resolve, where it stands, and
 * (for a single-game pick, the only shape with exactly two options) how the
 * huddle split. No client interactivity, so this stays a server component.
 */
export function PromptContext({ post }: { post: Post }) {
  const singleGameSlot = (isPicksPost(post) || post.isOpinion) && post.slots.length === 1 ? post.slots[0] : null;
  const split = singleGameSlot ? post.aggregate?.[singleGameSlot.id] : undefined;

  return (
    <aside aria-label="About this prompt" className="xl:sticky xl:top-[92px] xl:self-start">
      <div className="border border-line bg-surface-raised p-4 shadow-well">
        <p className="font-mono text-[10px] font-semibold tracking-[0.15em] text-hidden-text uppercase">Prompt details</p>
        <h2 className="mt-1 font-slab text-[27px] leading-none text-fg uppercase">About this prompt</h2>
        <div className="mt-4 border-t border-line">
          <div className="border-b border-line py-3.5">
            <p className="font-mono text-[10px] tracking-[0.1em] text-fg-muted uppercase">Resolves</p>
            <p className="mt-1.5 text-sm leading-6 text-fg">{post.resolutionCriteria}</p>
          </div>
          <div className={split ? "border-b border-line py-3.5" : "py-3.5"}>
            <p className="font-mono text-[10px] tracking-[0.1em] text-fg-muted uppercase">Status</p>
            <p className="mt-1.5 text-sm leading-6 text-fg">{statusLine(post)}</p>
          </div>
          {singleGameSlot && split ? (
            <div className="py-3.5">
              <p className="mb-2.5 font-mono text-[10px] tracking-[0.1em] text-fg-muted uppercase">How the huddle picked</p>
              <div className="flex flex-col gap-2">
                {singleGameSlot.options.map((option) => (
                  <div key={option.id} className="flex items-center gap-2">
                    <OptionIcon option={option} className="h-6 w-6" />
                    <span className="min-w-0 flex-1 truncate font-slab text-sm uppercase">{option.label}</span>
                    <span className="font-mono text-xs text-fg-muted tabular-nums">{split[option.id] ?? 0}%</span>
                  </div>
                ))}
              </div>
              <div className="mt-2.5 flex h-2 overflow-hidden border border-line">
                {singleGameSlot.options.map((option) => (
                  <span key={option.id} style={{ width: `${split[option.id] ?? 0}%` }} className="h-full bg-panel first:bg-panel last:bg-fg-muted/40" />
                ))}
              </div>
            </div>
          ) : null}
        </div>
      </div>
    </aside>
  );
}

function statusLine(post: Post): string {
  const people = `${post.responseCount} ${post.responseCount === 1 ? "person" : "people"} answered`;
  if (post.status === "void") return `Voided — ${post.voidReason ?? "no reason given"}`;
  if (post.status === "resolved") return `Resolved · ${people}`;
  if (post.status === "locked") return `Locked · ${people}`;
  return `Open · closes ${relativeTime(post.lockAt)}`;
}
