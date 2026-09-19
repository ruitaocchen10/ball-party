import { execFileSync } from "node:child_process";
import { readFileSync } from "node:fs";
import { join } from "node:path";
import { fileURLToPath } from "node:url";

const webappRoot = join(fileURLToPath(new URL("..", import.meta.url)));
const env = readFileSync(join(webappRoot, ".env.local"), "utf8");
const configured = env.match(/^PROMPTS_ADMIN_EMAILS=(.*)$/m)?.[1] ?? "";
const emails = [...new Set(configured.split(",").map((email) => email.trim().toLowerCase()).filter(Boolean))];

if (!emails.length || emails.some((email) => !/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(email))) {
  throw new Error("Set PROMPTS_ADMIN_EMAILS in webapp/.env.local to one or more comma-separated email addresses.");
}

const values = emails.map((email) => `('${email.replaceAll("'", "''")}')`).join(", ");
const sql = `insert into prompts_private.admin_config (email) values ${values} on conflict (email) do nothing;`;

execFileSync("supabase", ["db", "query", "--local", sql], { stdio: "inherit" });
