#!/usr/bin/env node
// Reset the local database, then restore the Storage assets that SQL seeds
// cannot represent. Invoke this instead of `supabase db reset` in local and CI
// workflows that need the franchise marks.

import { spawnSync } from "node:child_process";

function run(command, args, options = {}) {
  const result = spawnSync(command, args, { encoding: "utf8", ...options });
  if (result.error) throw result.error;
  if (result.status !== 0) {
    if (result.stderr) process.stderr.write(result.stderr);
    process.exit(result.status ?? 1);
  }
  return result.stdout;
}

function envFromStatus(status) {
  const env = {};
  for (const line of status.split(/\r?\n/)) {
    const match = line.match(/^([A-Z0-9_]+)=(.*)$/);
    if (match) {
      // `supabase status --output env` emits shell-quoted values. JSON parsing
      // removes those quotes without exposing the service-role key in logs.
      env[match[1]] = match[2].startsWith('"') ? JSON.parse(match[2]) : match[2];
    }
  }
  return env;
}

run("supabase", ["db", "reset"], { stdio: "inherit" });

const local = envFromStatus(run("supabase", ["status", "--output", "env"]));
if (!local.API_URL || !local.SERVICE_ROLE_KEY) {
  console.error("Could not read the local API URL and service-role key from `supabase status --output env`.");
  process.exit(1);
}

run(process.execPath, [new URL("./build_logos.mjs", import.meta.url).pathname], {
  stdio: "inherit",
  env: {
    ...process.env,
    SUPABASE_URL: local.API_URL,
    SUPABASE_SERVICE_ROLE_KEY: local.SERVICE_ROLE_KEY,
  },
});
