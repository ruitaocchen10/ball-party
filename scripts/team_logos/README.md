# Team logos

Sabotage draft's franchise logos: one PNG per franchise code, uploaded once
into the `team-logos` Supabase Storage bucket (see
[`supabase/migrations/*_sabotage_draft_team_logos_bucket.sql`](../../supabase/migrations)),
under `{franchise_code}.png` — the same PFR code
[`franchises.ts`](../../frontend/lib/sabotage-draft/franchises.ts) already
keys franchise identity on everywhere else in the app.

## Running it

```sh
SUPABASE_URL=https://<project>.supabase.co \
SUPABASE_SERVICE_ROLE_KEY=<service role key> \
node scripts/team_logos/build_logos.mjs
```

Needs the **service role** key, not the publishable one — this writes to a
bucket, not a read. Get it from the project's API settings, or (for a local
stack) `supabase status`. Never commit it.

A run-once ETL, in the same spirit as
[`scripts/av_roster_pool`](../av_roster_pool): the 32-franchise universe
barely changes — a relocation or rename is the only thing that would — so
there's no scheduler and no freshness logic. Rerun by hand when it does; a
rerun overwrites (`x-upsert`), it doesn't duplicate.

### Local reset

After `supabase start`, run `npm --prefix frontend run db:reset`. It resets
the database, obtains the local service-role key from `supabase status`, and
uploads all logo PNGs to local Storage. SQL seed files can create the bucket
but cannot write the PNG bytes, so calling `supabase db reset` directly stays
database-only.

## Source

[ESPN's public team-logo CDN](https://a.espncdn.com/i/teamlogos/nfl/500/),
one flat PNG per team abbreviation. Unlike PFR itself (see
[`../av_roster_pool/pfr_scrape.js`](../av_roster_pool/pfr_scrape.js)'s own
header), it sits behind no Cloudflare challenge and rate-limits nothing this
script's pace would hit, so a plain `fetch` works — no browser-console
procedure needed here.

ESPN's team abbreviations disagree with PFR's stable franchise codes for
every relocation PFR's code deliberately stayed put across — `clt`/`ind`,
`crd`/`ari`, `htx`/`hou`, `oti`/`ten`, `rav`/`bal`, `sdg`/`lac`, `rai`/`lv`,
`ram`/`lar` — plus a handful of plain spelling differences (`gnb`/`gb`,
`kan`/`kc`, `nor`/`no`, `nwe`/`ne`, `sfo`/`sf`, `tam`/`tb`, `was`/`wsh`). The
script carries its own crosswalk for this reason; it isn't folded into
`franchises.ts` because nothing in the app needs it — only this one-time
fetch does.

## Licensing — unreviewed, more so than the roster pool's

[`scripts/av_roster_pool/README.md`](../av_roster_pool/README.md) already
carries an explicit "licensing is unreviewed" caveat for PFR/nflverse's
*stats*. Team logos are real, trademarked NFL artwork — a step up in risk
from stats text, not a smaller one — and that same caveat applies here more
pointedly. This script exists because product direction asked for it, not
because the legal question has been settled; treat a real run against a
production bucket accordingly, same as that pool's own README asks for
itself.

## Shape

```
build_logos.mjs   fetch (ESPN CDN) + upload (Storage REST), no dependencies
```

No transform step and nothing to unit test here, unlike the roster pool:
there's no parsing, folding, or identity-reconciliation logic — just a fixed
32-entry crosswalk, a fetch, and an upload. `frontend/components/sabotage-
draft/TeamLogo.tsx` is what's actually exercised by tests; it's written to
degrade to text-only for any code this script hasn't (yet, or ever)
succeeded for, so a partial or never-run upload is never a hard failure for
the app itself.
