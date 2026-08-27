#!/usr/bin/env node
// Fetch each NFL franchise's logo once and upload it to the `team-logos`
// Supabase Storage bucket (see
// supabase/migrations/*_sabotage_draft_team_logos_bucket.sql), under
// `{franchise_code}.png` -- the PFR franchise code every other sabotage
// draft surface already keys on (frontend/lib/sabotage-draft/franchises.ts).
//
//   SUPABASE_URL=... SUPABASE_SERVICE_ROLE_KEY=... node scripts/team_logos/build_logos.mjs
//
// A run-once ETL, in the same spirit as scripts/av_roster_pool/build_pool.py
// and scripts/player_pool/build_pool.py: the 32-franchise universe barely
// changes (a relocation or rename is the only thing that would), so there is
// no scheduler and no freshness logic -- rerun by hand when it does.
//
// Node built-ins only for everything this script itself does (global fetch,
// Node 18+), the same "no new dependency for a run-once script" rule
// scripts/av_roster_pool/build_pool.py states for itself. The application
// never imports any of this.
//
// Source: ESPN's public team-logo CDN. Unlike PFR (see
// scripts/av_roster_pool/pfr_scrape.js's header), it sits behind no
// Cloudflare challenge and rate-limits nothing this script's pace would hit,
// so a plain fetch works. See this directory's README for the licensing
// caveat that comes with using it -- read it before running this against a
// real project.

const SUPABASE_URL = process.env.SUPABASE_URL;
const SERVICE_ROLE_KEY = process.env.SUPABASE_SERVICE_ROLE_KEY;
const BUCKET = "team-logos";

if (!SUPABASE_URL || !SERVICE_ROLE_KEY) {
  console.error("Set SUPABASE_URL and SUPABASE_SERVICE_ROLE_KEY (the service role key -- this writes to a bucket, not a read a publishable key can do).");
  process.exit(1);
}

// PFR's own stable franchise code (see franchises.ts's own header on why
// that's the identity every sabotage draft surface keys on) -> ESPN's team
// abbreviation, needed only because ESPN's CDN path uses ESPN's own
// abbreviations, which disagree with PFR's for every franchise relocation
// PFR's code deliberately stayed stable across (clt/crd/htx/oti/rav/sdg/
// rai/ram, plus a handful of plain spelling differences). Kept as its own
// table, not folded into franchises.ts, because nothing in the app needs
// this crosswalk -- only this one-time fetch does.
const ESPN_ABBR = {
  atl: "atl", buf: "buf", car: "car", chi: "chi", cin: "cin", cle: "cle",
  clt: "ind", crd: "ari", dal: "dal", den: "den", det: "det", gnb: "gb",
  htx: "hou", jax: "jax", kan: "kc", mia: "mia", min: "min", nor: "no",
  nwe: "ne", nyg: "nyg", nyj: "nyj", oti: "ten", phi: "phi", pit: "pit",
  rai: "lv", ram: "lar", rav: "bal", sdg: "lac", sea: "sea", sfo: "sf",
  tam: "tb", was: "wsh",
};

async function fetchLogo(espnAbbr) {
  const url = `https://a.espncdn.com/i/teamlogos/nfl/500/${espnAbbr}.png`;
  const response = await fetch(url);
  if (!response.ok) throw new Error(`fetch ${url}: ${response.status}`);
  return new Uint8Array(await response.arrayBuffer());
}

async function upload(code, bytes) {
  // Storage's own REST upload endpoint, not the supabase-js SDK: two REST
  // calls don't earn a new dependency for a run-once script (see this file's
  // own header). x-upsert makes a rerun overwrite rather than 409, since a
  // franchise's logo can be refreshed by running this again.
  const url = `${SUPABASE_URL}/storage/v1/object/${BUCKET}/${code}.png`;
  const response = await fetch(url, {
    method: "POST",
    headers: {
      Authorization: `Bearer ${SERVICE_ROLE_KEY}`,
      "Content-Type": "image/png",
      "x-upsert": "true",
    },
    body: bytes,
  });
  if (!response.ok) throw new Error(`upload ${code}: ${response.status} ${await response.text()}`);
}

async function main() {
  const failures = [];
  for (const [code, espnAbbr] of Object.entries(ESPN_ABBR)) {
    try {
      const bytes = await fetchLogo(espnAbbr);
      await upload(code, bytes);
      console.log(`${code}: ok`);
    } catch (error) {
      failures.push(code);
      console.error(`${code}: ${error.message}`);
    }
  }
  if (failures.length) {
    // Not fatal on its own -- TeamLogo.tsx falls back to text-only for any
    // code with no file behind it -- but worth a non-zero exit so a CI/manual
    // run notices rather than assumes every franchise made it.
    console.error(`${failures.length} franchise(s) failed: ${failures.join(", ")}`);
    process.exit(1);
  }
}

await main();
