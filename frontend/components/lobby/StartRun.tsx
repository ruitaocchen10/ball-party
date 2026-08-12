import { Button } from "@/components/ui/Button";
import { startRun } from "@/lib/lobbies/actions";

/**
 * The control that turns a room into a game. Host only, because a game
 * beginning while somebody is still explaining the rules is the thing the
 * host-only check exists to prevent — the RPC enforces it either way, so this
 * is the honest rendering of a rule rather than the rule itself.
 *
 * Disabled below two players with the reason next to it. The database has its
 * own floor and will refuse; saying so before the tap is what stops it reading
 * as a broken button.
 */
export function StartRun({
  lobbyId,
  code,
  players,
}: {
  lobbyId: string;
  code: string;
  players: number;
}) {
  const short = players < 2;

  return (
    <form action={startRun} className="flex flex-col gap-2">
      <input type="hidden" name="lobby_id" value={lobbyId} />
      <input type="hidden" name="code" value={code} />
      <label className="flex flex-col gap-1 font-mono text-[10px] tracking-[0.13em] text-panel-muted uppercase">
        Scoring
        <select
          aria-label="Scoring"
          name="scoring_mode"
          defaultValue="weekly"
          className="min-h-10 rounded border border-[#c7bfac] bg-panel px-2 text-sm tracking-normal text-panel-fg normal-case"
        >
          <option value="weekly">Weekly</option>
          <option value="season_total">Season total</option>
        </select>
      </label>
      <label className="flex flex-col gap-1 font-mono text-[10px] tracking-[0.13em] text-panel-muted uppercase">
        Roster
        <select
          aria-label="Roster"
          name="roster_preset"
          defaultValue="standard"
          className="min-h-10 rounded border border-[#c7bfac] bg-panel px-2 text-sm tracking-normal text-panel-fg normal-case"
        >
          <option value="standard">Standard · 20 lots</option>
          <option value="full">Full · 28 lots</option>
          <option value="deep">Deep · 40 lots</option>
        </select>
      </label>
      <Button type="submit" disabled={short}>
        Start the auction
      </Button>
      {short ? (
        <p className="font-mono text-[10px] tracking-[0.13em] text-fg-muted uppercase">
          Waiting for one more player
        </p>
      ) : null}
    </form>
  );
}
