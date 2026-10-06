import { Button } from "@/components/foundation/ui-kit/Button";
import { goToLobby } from "@/lib/platform/lobbies/actions";

/**
 * Join by code, as a dark panel beside the cream "start a room" card.
 *
 * The field and its button share one border so they read as a single control
 * rather than two boxes that happen to sit together. The well is the darkest
 * surface because it sits on a raised panel, and raised-on-raised has nothing
 * to read against.
 *
 * Rendered once per page, so the label can bind to a fixed id.
 */
export function JoinRoom() {
  return (
    <section
      aria-labelledby="join-room-heading"
      className="flex flex-col border border-line bg-surface-raised p-4 shadow-well sm:p-5"
    >
      <p className="type-label font-semibold text-hidden-text">Someone else hosts</p>
      <h2 id="join-room-heading" className="mt-2 font-slab text-2xl leading-none uppercase">
        Join with a code
      </h2>
      <p className="mt-3 text-[13.5px] leading-[1.5] text-fg-muted">
        Got five characters by text? Type them here — you&apos;ll land straight in their room.
      </p>

      <form
        action={goToLobby}
        className="mt-auto flex h-12 items-center border border-line bg-surface transition-colors focus-within:border-panel/70"
      >
        <label htmlFor="join-code" className="sr-only">
          Room code
        </label>
        <input
          id="join-code"
          name="code"
          required
          maxLength={5}
          autoCapitalize="characters"
          autoComplete="off"
          spellCheck={false}
          placeholder="K7M2Q"
          className="h-full min-w-0 flex-1 bg-transparent pl-4 font-mono text-[15px] tracking-[0.2em] text-fg uppercase outline-none placeholder:text-fg-muted"
        />
        <Button type="submit" size="sm" fullWidth={false} className="my-1 mr-1 h-10">
          Join
        </Button>
      </form>
    </section>
  );
}
