# stats — /stats/ page (2026-11-19). Spec lives in the private desk repo.
- Page = site/src/stats/: index.html + p-*.html partials (bands 00-11), css/*.css (bundled to one hashed file),
  js/stats.js (core: fetch, schema guard, formats, readout, reveal) + stats-a..d.js (charts, `JStats.charts[name]`).
- Only data.json fields go in (schema jiva-token-stats/1 or /2). Labels are Repo A…, misc, No repo, Box 1…3.
- Build: scripts/stats_build.py (called by build.py after fingerprint) fills every `data-stat` span and
  `<!-- @table x -->` from data.json via stats_data.py, so the page reads with JS off; renders crosslinks.txt;
  hashes css/js/data + SRI; publishes /stats/data.json (pretty, citable) + data.<h>.json (minified, fetched).
- stats_data.FMT mirrors JStats.f: change both; stats_test.cjs (node) diffs them in site-check.
- Money: every band with a `$` carries money.html ("API-equivalent, not what we pay") and data-money;
  stats_check.py fails a band without it; JStats.usd() throws outside such a band.
- stats_scrub.py (site-check): self-test (16 plants) + default-deny keys/strings + deny patterns over data.json
  and the rendered page. New dataset field or note string = add it to WORDS/NOTES there (deliberate).
  `JIVA_STATS_DENY=<file>` adds private real names (the desk passes it; never commit such a file).
- Crosslinks: src/stats/crosslinks.txt, default deny; HOLD in stats_check.py = sha256[:16] of unreleased names.
  Release a held tool: add its line + drop its hash, same commit.
- Refresh (desk): `just token-stats` → `just jiva-stats-sync` (refusals: missing/>24h/schema/self-test/dirty
  stats dir) or `just jiva-stats-deploy` (commits data.json alone, push, `just deploy`, verify).
- Motion: host gets .go once on scroll-in; transform/opacity/clip-path/dashoffset only; reduced motion = .go at once,
  no count-ups, static before/after for the rotation band.
- 2026-11-19 proof (local serve, mobile Lighthouse): stats 98/100/96/100 (BP 96 = CSP frame-ancestors meta warning,
  same as index). Own files 107 KB (budget 120). jsdom: all 11 charts draw, no NaN, 390 + 1280 + reduced.
  390px: no horizontal overflow (checked in Chromium).
