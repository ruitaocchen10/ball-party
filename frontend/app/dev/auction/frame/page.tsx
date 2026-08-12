/**
 * The auction screen with nothing around it, for the phone iframe on
 * /dev/auction. Its own document, so the build's viewport-based `lg:`
 * breakpoints resolve against the frame's width rather than the window's.
 */

import { Frame } from "./Frame";

export default async function AuctionFramePage({
  searchParams,
}: {
  searchParams: Promise<{ state?: string; secs?: string; stamp?: string }>;
}) {
  const { state, secs, stamp } = await searchParams;
  return <Frame state={state} secs={secs} stamp={stamp} />;
}
