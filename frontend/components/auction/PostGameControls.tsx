import { Button } from "@/components/ui/Button";
import { postGameChoice } from "@/lib/lobbies/actions";

/** The host advances the shared room; everybody else can keep reading results. */
export function PostGameControls({
  matchId,
  roomCode,
  isHost,
}: {
  matchId: string;
  roomCode: string;
  isHost: boolean;
}) {
  if (!isHost) {
    return <p className="text-sm text-fg-muted">Waiting for the host to choose what’s next.</p>;
  }

  return (
    <div className="mt-2 flex flex-col gap-2">
      <form action={postGameChoice}>
        <input type="hidden" name="match_id" value={matchId} />
        <input type="hidden" name="room_code" value={roomCode} />
        <input type="hidden" name="choice" value="replay" />
        <Button type="submit" fullWidth>Replay</Button>
      </form>
      <form action={postGameChoice}>
        <input type="hidden" name="match_id" value={matchId} />
        <input type="hidden" name="room_code" value={roomCode} />
        <input type="hidden" name="choice" value="lobby" />
        <Button type="submit" variant="ghost" fullWidth>Back to lobby</Button>
      </form>
    </div>
  );
}
