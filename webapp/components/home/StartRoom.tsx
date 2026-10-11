import { Button, ButtonLink } from "@/components/foundation/ui-kit/Button";
import { createLobby } from "@/lib/platform/lobbies/actions";
import { HOST_SIGN_UP_HREF } from "@/lib/platform/lobbies/hosting";

/**
 * The host entry point on the party screen, with an honest account gate for
 * temporary players. The light card: opening a room is the primary path, so it stands out
 * against the dark join card beside it.
 */
export function StartRoom({ canCreateLobby }: { canCreateLobby: boolean }) {
  return (
    <div className="relative flex flex-col overflow-hidden rounded-card bg-fg p-4 text-surface shadow-card sm:p-5">
      <p className="type-label font-semibold text-surface/60">{canCreateLobby ? "You host" : "Account required"}</p>
      <h2 className="mt-2 font-slab text-2xl leading-none uppercase">Start a room</h2>
      <p className="mt-3 text-[13.5px] leading-[1.5] text-surface/75">
        {canCreateLobby
          ? "Opens a five-character code. Send it to three friends and pick a game once they're in."
          : "Hosting needs an account. Join a friend to play, or sign up to open your own room."}
      </p>
      <div className="mt-auto pt-5">
        {canCreateLobby ? (
          <form action={createLobby}>
            <Button type="submit" variant="dark" fullWidth={false} className="px-7">
              Start a room
            </Button>
          </form>
        ) : (
          <ButtonLink href={HOST_SIGN_UP_HREF} variant="dark" fullWidth={false} className="px-7">
            Create an account to host
          </ButtonLink>
        )}
      </div>
    </div>
  );
}
