import { Button, ButtonLink } from "@/components/ui/Button";
import { WayIn } from "@/components/home/WayIn";
import { createLobby } from "@/lib/lobbies/actions";
import { HOST_SIGN_UP_HREF } from "@/lib/lobbies/hosting";

/** The host entry point on the home screen, with an honest account gate for guests. */
export function StartRoom({ canCreateLobby }: { canCreateLobby: boolean }) {
  return (
    <WayIn
      kicker={canCreateLobby ? "You host" : "Account required"}
      title="Start a room"
      body={
        canCreateLobby
          ? "Opens a five-character code. Send it to three friends and pick a game once they're in."
          : "Hosting needs an account. Join a friend as a guest, or sign up to open your own room."
      }
      lit
    >
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
    </WayIn>
  );
}
