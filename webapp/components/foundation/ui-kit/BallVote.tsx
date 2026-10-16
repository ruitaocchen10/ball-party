import { ThumbsDown, ThumbsUp } from "lucide-react";

/** A football, outlined, or filled leather when `filled`. Takes the surrounding text colour for the outline. */
export function FootballIcon({ filled = false, className = "h-[18px] w-[18px]" }: { filled?: boolean; className?: string }) {
  return (
    <svg viewBox="0 0 24 24" aria-hidden="true" className={className} fill="none" stroke="currentColor" strokeWidth={1.6} strokeLinecap="round">
      <g transform="rotate(-35 12 12)">
        <ellipse cx="12" cy="12" rx="10.5" ry="6.4" className={filled ? "fill-ball stroke-ball" : undefined} />
        <path d="M7.6 12h8.8M9.6 10.3v3.4M12 10.1v3.8M14.4 10.3v3.4" className={filled ? "stroke-fg" : undefined} />
        <path d="M3.6 9.6c1 .9 1.5 1.5 1.5 2.4s-.5 1.5-1.5 2.4M20.4 9.6c-1 .9-1.5 1.5-1.5 2.4s.5 1.5 1.5 2.4" className={filled ? "stroke-fg" : undefined} />
      </g>
    </svg>
  );
}

/**
 * Thumbs up, the take's net count, thumbs down. Give a ball and the thumb
 * turns into a leather football, so the like reads as "you gave a ball". A
 * thumb is drawn only when the viewer may use it, so a stranger sees up and
 * the count, and your own take shows just the count. No container: it sits
 * in the card's action row beside the comment icon.
 *
 * Purely presentational: the parent owns the number and the calls.
 */
export function BallVote({
  net,
  mine,
  canLike,
  canDislike,
  pending = false,
  onLike,
  onDislike,
}: {
  net: number;
  mine: -1 | 0 | 1;
  canLike: boolean;
  canDislike: boolean;
  pending?: boolean;
  onLike: () => void;
  onDislike: () => void;
}) {
  const button = "inline-flex h-8 w-6 items-center justify-center rounded-full transition-colors disabled:opacity-60 focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-fg";
  return (
    <div role="group" aria-label="Balls" className="inline-flex items-center gap-2">
      {!canLike && !canDislike ? (
        // Your own take, or a reader who cannot react: the football and the count.
        <span aria-label={`${net} ${Math.abs(net) === 1 ? "ball" : "balls"}`} className={`inline-flex h-8 items-center gap-1.5 font-mono text-xs font-bold tabular-nums ${net > 0 ? "text-ball" : "text-fg-muted"}`}>
          <FootballIcon filled={net > 0} className="h-[22px] w-[22px]" />
          {net}
        </span>
      ) : null}
      {canLike ? (
        <button
          type="button"
          aria-label={mine === 1 ? "Take back your ball" : "Give a ball"}
          aria-pressed={mine === 1}
          disabled={pending}
          onClick={onLike}
          className={`${button} ${mine === 1 ? "text-ball" : "text-fg-muted hover:text-fg"}`}
        >
          {mine === 1 ? <FootballIcon filled className="h-6 w-6" /> : <ThumbsUp className="h-5 w-5" strokeWidth={1.8} />}
        </button>
      ) : null}
      {canLike || canDislike ? (
        <span
          aria-label={`${net} ${Math.abs(net) === 1 ? "ball" : "balls"}`}
          className={`min-w-4 text-center font-mono text-xs font-bold tabular-nums ${mine === 1 ? "text-ball" : "text-fg-muted"}`}
        >
          {net}
        </span>
      ) : null}
      {canDislike ? (
        <button
          type="button"
          aria-label={mine === -1 ? "Take back your dislike" : "Take a ball away"}
          aria-pressed={mine === -1}
          disabled={pending}
          onClick={onDislike}
          className={`${button} ${mine === -1 ? "text-fg" : "text-fg-muted hover:text-fg"}`}
        >
          <ThumbsDown className="h-5 w-5" strokeWidth={1.8} fill={mine === -1 ? "currentColor" : "none"} />
        </button>
      ) : null}
    </div>
  );
}
