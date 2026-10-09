# QB Season Builder — Madden data: license posture

The talent layer blends Madden ratings with stats (recipe and weights:
`scripts/qb_ratings/config.py`). This records why that is allowed to ship and
the conditions that keep it that way. Code comments cite the numbered
conditions below.

## Decision

**GO. The owner accepted the license risk on 2026-09-20.** This is a business
decision to proceed without a license, not a finding that the use is permitted.
No lawyer has reviewed it.

Why there is no license to lean on: the source dataset
([`theedgepredictor/nfl-madden-data`](https://github.com/theedgepredictor/nfl-madden-data),
snapshot `7443ba1`) has no license, so default copyright applies; it scrapes a
fan site (`maddenratings.net`) that publishes no terms and has no rights to
grant; and EA, the originator, reserves its rights and offers no data license.
The "John Madden" mark is separately licensed to EA.

## Conditions

1. **Private and derived only.** Source ratings live only in a private table no
   client role can read. The app, result page and API expose blended values
   only, never a Madden input, name or brand.
2. **The migration that loads the ratings must never reach a public
   repository.** The repo was private on 2026-09-20. If it is ever made public,
   strip the Madden layer (and any snapshot) first.
3. **Reversible by configuration.** Set the Madden column of `WEIGHTS` in
   `scripts/qb_ratings/config.py` to 0 (`STAT_ONLY`) and delete the private
   table. The game continues on stats alone with no schema, API or rule changes.
4. **Never vendor the dataset.** The pipeline reads a local snapshot
   (`--madden-dir`) and never fetches, links to, mirrors or re-hosts it.

## Dataset facts the pipeline relies on

- File `S` is the edition released in August of season `S` (file 2010 = Madden
  NFL 11). The edition after season `S` is file `S+1`; the pre-season fallback
  is file `S`.
- Use `processed/` (observed ratings), never `dataset/` (model-imputed
  estimates that would hide gaps).
- Coverage of the 778 qualifying QB team-seasons (150+ pass attempts), 2006-2025:
  96.4% have an observed rating. Two seasons are near-total fallbacks to the
  pre-season edition: 2008 (the Madden NFL 10 sheet is a stub) and 2025 (no
  later edition in the dataset). The 28 with no rating in either edition (mostly
  backups) use stats only for that row. Madden NFL 25 (file 2013) has no
  acceleration column.
- The build fails if fewer than 85% of Supporting Cast roster spots resolve to
  a rating; 92.5% did when measured.
