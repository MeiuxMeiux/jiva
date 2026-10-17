# dash — tier-1 dashboard
Run: `just dash` (start, prints URL) · `just dash url` · `just dash stop`. `just down` also stops it.
- python3 http.server, `--bind 127.0.0.1`, port: JIVA_DASH_PORT, else sticky .jiva/dash/port, else `shuf -i 20000-60000` (6 tries).
- pid/port in `.jiva/dash/{pid,port}`; server is `setsid` so it outlives the calling shell.
- Web root is `.jiva/dash/www/` = symlinks only (see dash.sh header); state.json → .jiva/state.json.
  Symlink (not copy loop) works because watchdog writes state.json via atomic mv; the link resolves by name.
  http.server rejects `..` (raw and %2e%2e tested → 404), so board.log/handoff/tasks/claims are unreachable.
- Page: fetch every 5s (no-store), repaint age every 1s; greys out when ts >30s old; red banner on flags>0
  or fetch failure. All values rendered via textContent; strings filtered to [\w .:-] ≤24 chars.
- CSP: default-src 'none'; connect-src/img/style/font/script 'self' — no 'unsafe-inline'. Styles live in core/dash.css
  (base, tiles, scrollbars) + dash-parts.css (table, panels); JS sets only CSS custom props (--slot) via setProperty.
- Look = site palette (tokens.css hexes), fonts/ = per-file woff2 symlinks (no OFL txt), chamfer clip-path, icon sprite
  <symbol>s in dash.html + icon() in dash-panels.js. Doctor greps scrollbar rules with comments stripped.
- fleet usd tile is summed client-side; state.json has no top-level usd.
- /board = {last: per-name last board line {name,ts,age,verb,text}, tail: last 20, quiet: [names]} — table "doing" column + Board panel.
- /alerts = last 20 notify.log lines `<epoch> <text>` → [{ts,age,text}] newest first; malformed lines skipped.
- Panels live in core/dash-panels.js (loaded before dash.js, shares its globals). Alerts panel under Board; newest alert <10 min → amber "ALERT <text>" banner.
- Port is sticky: stop keeps .jiva/dash/port; start tries it first (bind fails if taken → re-roll). Live bookmark = 34517.
- API lives in core/dash-api.py. /commits?before=&n≤100 + /commit/<sha> (numstat only) run git -C DTARGET; doctor uses a scratch repo.
- Phone (tier-2, local only): `just snapshot` → core/snapshot.sh writes .jiva/snapshot/snapshot.json via jq allowlist
  (strings re-filtered to [A-Za-z0-9_.-]≤24; asks = id/class/age, never text); dash serves it + phone.{html,css,js}.
  Watchdog hook (w2's) would be one line per tick: `"$JIVA_HOME/core/snapshot.sh" >/dev/null 2>&1 || true`.
- Hosting = human ask, not built: (a) tailscale serve the dash port to the tailnet; (b) rsync snapshot.json + phone.*
  + fonts/ to a static host behind auth; (c) outbound push of snapshot.json to an object bucket the phone reads.
- History (core/dash_hist.py, loaded by path — python -I drops the script dir): /history?before=<ts>&n≤500&kind=&name= reads
  history.jsonl backwards in 64k blocks, re-allowlists fields per kind, completes a ts tie at the page edge; name = row.name
  (session events) else who (ask/ship always who). /history/summary cached on (mtime,size): ≤200 buckets, lanes + last tok/bucket.
- Panel = core/dash-history.js: tok + quota sparklines (two charts, no dual axis), SVG timeline, chips, infinite list; souls via state.json sessions[].soul.
- Faces: soul() (dash.js) = state soul binding → pack slot; face(av, sl, name) tries portrait webp → svg → initial. Party strip
  (#party, party() in dash-panels.js) + history chips use it; phone maps snapshot slot → pack.json; snapshot slot/color = sessions[].soul (wN→N only if absent), name stays wN.
