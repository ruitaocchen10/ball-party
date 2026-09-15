import { defineConfig, globalIgnores } from "eslint/config";
import nextVitals from "eslint-config-next/core-web-vitals";
import nextTs from "eslint-config-next/typescript";

const eslintConfig = defineConfig([
  ...nextVitals,
  ...nextTs,
  // Override default ignores of eslint-config-next.
  globalIgnores([
    // Default ignores of eslint-config-next:
    ".next/**",
    "out/**",
    "build/**",
    "next-env.d.ts",
  ]),
  {
    // docs/architecture/architecture.md: "a game may depend on the contract,
    // content, and the UI kit. A game may never import lobbies or
    // orchestration." foundation/* and runtime/* stay unrestricted.
    files: ["components/games/**/*.{ts,tsx}", "lib/games/**/*.{ts,tsx}"],
    rules: {
      "no-restricted-imports": [
        "error",
        {
          patterns: [
            {
              group: ["@/components/platform/*", "@/lib/platform/*"],
              message: "A game may never import platform (lobbies/orchestration) directly — see docs/architecture/architecture.md.",
            },
          ],
        },
      ],
    },
  },
]);

export default eslintConfig;
