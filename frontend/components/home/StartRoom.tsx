import { Button } from "@/components/ui/Button";
import { WayIn } from "@/components/home/WayIn";
import { createLobby } from "@/lib/lobbies/actions";

/** The signed-in host entry point on the home screen. */
export function StartRoom() {
  return (
    <WayIn
      kicker="You host"
      title="Start a room"
      body="Opens a five-character code. Send it to three friends and pick a game once they're in."
      lit
    >
      <form action={createLobby}>
        <Button type="submit" variant="ink" fullWidth={false} className="px-7">
          Start a room
        </Button>
      </form>
    </WayIn>
  );
}
