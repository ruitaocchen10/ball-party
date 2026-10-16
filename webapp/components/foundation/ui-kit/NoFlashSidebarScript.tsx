"use client";

// Runs before first paint so a reload lands at the sidebar width the user
// last chose instead of flashing expanded-then-collapsing. Mirrors the
// classic no-flash dark-mode script — same reasoning, one attribute.
const NO_FLASH_SIDEBAR_SCRIPT = `
  try {
    if (localStorage.getItem("sidebar-collapsed") === "true") {
      document.documentElement.setAttribute("data-sidebar-collapsed", "");
    }
  } catch (e) {}
`;

/**
 * The script above, written into the server-rendered HTML only.
 *
 * React 19 logs "Encountered a script tag while rendering React component"
 * whenever the browser renders a <script> element, and it does in dev when it
 * rebuilds the tree from the server payload. The script has already run by
 * then, so on the client this renders nothing. React skips unexpected nodes in
 * <head> when it hydrates, so the missing element is not a mismatch; the
 * suppress flag covers the one attribute it does compare. This is the
 * workaround next-themes uses for its own no-flash script.
 */
export function NoFlashSidebarScript() {
  if (typeof window !== "undefined") return null;
  return <script suppressHydrationWarning dangerouslySetInnerHTML={{ __html: NO_FLASH_SIDEBAR_SCRIPT }} />;
}
