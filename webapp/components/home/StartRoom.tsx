import { Button, ButtonLink } from "@/components/foundation/ui-kit/Button";
import { Card } from "@/components/foundation/ui-kit/Card";
import { createLobby } from "@/lib/platform/lobbies/actions";
import { HOST_SIGN_UP_HREF } from "@/lib/platform/lobbies/hosting";

/**
 * The host entry point on the party screen, with an honest account gate for
 * temporary players. The cream card: opening a room is the primary path, and
 * nothing is concealed yet, so no red edge.
 */
export function StartRoom({ canCreateLobby }: { canCreateLobby: boolean }) {
  return (
    <Card edge={false} className="flex flex-col p-4 sm:p-5">
      <p className="type-label font-semibold text-hidden-ink">{canCreateLobby ? "You host" : "Account required"}</p>
      <h2 className="mt-2 font-slab text-2xl leading-none uppercase">Start a room</h2>
      <p className="mt-3 text-[13.5px] leading-[1.5] text-panel-soft">
        {canCreateLobby
          ? "Opens a five-character code. Send it to three friends and pick a game once they're in."
          : "Hosting needs an account. Join a friend to play, or sign up to open your own room."}
      </p>
      <div className="mt-auto pt-5">
        {canCreateLobby ? (
          <form action={createLobby}>
            <Button type="submit" variant="ink" fullWidth={false} className="px-7">
              Start a room
            </Button>
          </form>
        ) : (
          <ButtonLink href={HOST_SIGN_UP_HREF} variant="ink" fullWidth={false} className="px-7">
            Create an account to host
          </ButtonLink>
        )}
      </div>
    </Card>
  );
}
