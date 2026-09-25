/** The account-creation route used wherever a visitor tries to host. Sends
 *  them back to Party — the room-hosting controls that sent them here live on
 *  that page, not on the home landing page. */
export const HOST_SIGN_UP_HREF = "/signup?next=%2Fparty";

/** The account-creation route for a signed-out visitor who followed an
 *  invite link. Sends them back to that specific room, since join_lobby
 *  rejects a guest server-side and the invite is the one flow they came for. */
export function joinSignUpHref(code: string): string {
  return `/signup?next=${encodeURIComponent(`/lobby/${code}`)}`;
}
