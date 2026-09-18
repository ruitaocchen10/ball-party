import { ButtonLink } from "@/components/foundation/ui-kit/Button";
import { joinSignUpHref } from "@/lib/platform/lobbies/hosting";

/** The invite landing for a signed-out visitor. Multiplayer requires a real
 *  account (join_lobby rejects a guest server-side), so this no longer offers
 *  a guest-name form that would only fail once submitted — only account
 *  creation, or sign-in for a visitor who already has one. Mirrors the honest
 *  account gate StartRoom uses for hosting. */
export function InviteAccountGate({ code }: { code: string }) {
  return (
    <div className="flex flex-col gap-2.5">
      <p className="text-sm leading-6 text-fg-muted">
        You&apos;ve been invited to this room. Multiplayer needs a real account — solo is still free to play as a guest.
      </p>
      <ButtonLink href={joinSignUpHref(code)} variant="ink" fullWidth={false} className="px-7">
        Create an account to join
      </ButtonLink>
      <ButtonLink href={`/login?next=${encodeURIComponent(`/lobby/${code}`)}`} variant="ghost">
        Sign in instead
      </ButtonLink>
    </div>
  );
}
