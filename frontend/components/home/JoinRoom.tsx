import { goToLobby } from "@/lib/lobbies/actions";

/**
 * Join by code. This sits in the page rather than in the top bar because it is
 * one of the two things you can do from home — the other being to start a room
 * — and the bar is chrome. Sized to match <Button> so the pair reads as two
 * actions of equal standing.
 *
 * The field and its button share one border so they read as a single control
 * rather than two boxes that happen to sit together.
 *
 * `inPanel` is for the copy that lives inside the "join with a code" panel on
 * the home screen: there it owns the full width, so the field stretches and
 * Join sits at the far edge, and the well drops to the darkest surface because
 * raised-on-raised has nothing to read against.
 *
 * Rendered once per page, so the label can bind to a fixed id.
 */
export function JoinRoom({
  className = "",
  inPanel = false,
}: {
  className?: string;
  inPanel?: boolean;
}) {
  return (
    <form
      action={goToLobby}
      className={`flex h-12 items-center border border-line transition-colors focus-within:border-panel/70 ${
        inPanel ? "bg-surface" : "bg-surface-raised"
      } ${className}`}
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
        className={`h-full min-w-0 flex-1 bg-transparent pl-4 font-mono text-[15px] tracking-[0.2em] text-fg uppercase outline-none placeholder:text-fg-muted ${
          inPanel ? "" : "sm:w-[122px] sm:flex-none"
        }`}
      />
      <button
        type="submit"
        className="my-1 mr-1 h-10 shrink-0 cursor-pointer bg-panel px-4 font-slab text-[13px] tracking-[0.04em] text-panel-fg uppercase transition-colors hover:bg-[#fffdf7] focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-panel"
      >
        Join
      </button>
    </form>
  );
}
