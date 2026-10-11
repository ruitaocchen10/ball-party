import { Card, CardMeta, CardTitle } from "@/components/foundation/ui-kit/Card";

/**
 * Shown to every player, host included, while the match is paused — the
 * thing that tells everyone else this is a deliberate freeze, not a hang.
 */
export function PauseBanner() {
  return (
    <Card className="text-center">
      <CardTitle>Paused</CardTitle>
      <CardMeta>The host paused the game. Hang tight.</CardMeta>
    </Card>
  );
}
