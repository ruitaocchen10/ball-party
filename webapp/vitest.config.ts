import react from "@vitejs/plugin-react";
import tsconfigPaths from "vite-tsconfig-paths";
import { defineConfig } from "vitest/config";

/**
 * The behaviour seam for the match screen.
 *
 * jsdom rather than a real browser, on purpose: everything asserted here is
 * behaviour the component decides — which phase is live, which controls are
 * enabled, what the status line says, where focus goes. Anything that only a
 * CSS engine can answer (the stacked/side-by-side breakpoint, whether the page
 * scrolls, whether the urgent colour is actually red) is out of reach here and
 * is called out as such in the suite rather than faked with a class assertion.
 */
export default defineConfig({
  plugins: [tsconfigPaths(), react()],
  test: {
    environment: "jsdom",
    globals: true,
    // Call history is per-test. Without this the shared scrollTo stub on
    // HTMLElement.prototype accumulates across a whole file, and any
    // toHaveBeenCalledWith against it passes on an earlier test's mount.
    clearMocks: true,
    setupFiles: ["./test/setup.ts"],
    include: ["**/*.test.tsx", "**/*.test.ts"],
    exclude: ["node_modules/**", ".next/**"],
  },
});
