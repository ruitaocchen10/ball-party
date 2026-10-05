# Sabotage draft — data decisions

Why the non-skill-position pool (OL/DL/LB/CB/S/ST, priced in Approximate Value)
has the shape it has. The pipeline lives in
[`scripts/av_roster_pool/`](../../../scripts/av_roster_pool/README.md). Facts were
checked against fetched Pro Football Reference (PFR) pages and nflverse files
in August 2026.

## 1. Source and era floor

PFR publishes position and AV together on `teams/{code}/{year}_roster.htm`.
PFR's `pos` strings are not stable across eras: modern rosters use `CB`, `S`,
`DT`, while older ones encode side and role (`LCB`/`RCB`, `SS`/`FS`, `LDT`,
`LOLB`/`MLB`). The pipeline folds them into the game's slots, and mid-season
trades put a player on two teams' rosters, each with a partial-season AV.

- **AV exists only from 1960**, and its defensive formula counts tackles only
  from 1994.
- **Era floor is 2006.** nflverse `nfldata/rosters.csv` covers 2006-2019 with AV
  and needs no scraping. Only 2020-present (about 192 team-season pages) is
  scraped from PFR, against about 780 pages for the earlier 1985 floor. A 2006
  floor also sits past the 1994 seam, so every season's defensive AV uses the
  same inputs. The cost is losing 1985-2005 history (Marino's early prime, Payton,
  Lawrence Taylor, the '85 Bears).

## 2. Team identity across history

PFR keeps **one stable 3-letter franchise code across every relocation and
rename**, and roster URLs use that code: `oti` renders the 1975 Houston Oilers
and the modern Titans, `crd` spans the Chicago through Arizona Cardinals, `ram`
the Cleveland through Los Angeles Rams. The game stores this code
(`franchise_code`), so "this franchise, any year" is one column. The display
names are in `webapp/lib/foundation/content/nfl/franchises.ts`.

## 3. Access constraints

- **No API or bulk export.** Sports Reference's data-use policy says it cannot
  provide downloads, and custom data requests start at $5,000.
- **Rate limit: 20 requests per minute** on PFR, enforced by a block of up to a
  day.
- **Cloudflare JS challenge** on PFR, so a plain HTTP fetch fails and the scrape
  needs a real browser session. `robots.txt` does not disallow roster pages for
  a generic user agent.
- **Terms of use are restrictive about automated access and were not
  legally reviewed.** nflverse licensing is likewise unreviewed. Keep the
  scrape small and cached (the reason for the 2006 floor).
