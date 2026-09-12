/** The account-creation route used wherever a visitor tries to host. Sends
 *  them back to Party — the room-hosting controls that sent them here live on
 *  that page, not on the home landing page. */
export const HOST_SIGN_UP_HREF = "/signup?next=%2Fparty";

/** The account-creation route used wherever a signed-out visitor reaches for
 *  a solo game — the sidebar's Solo games section included. Sends them back
 *  to /solo rather than wherever they clicked from: that page still has the
 *  "Play solo" flow those links stand in for. */
export const SOLO_SIGN_UP_HREF = "/signup?next=%2Fsolo";
