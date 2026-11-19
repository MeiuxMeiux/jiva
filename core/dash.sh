#!/usr/bin/env bash
# dash — tier-1 dashboard: stdlib python3 http.server on 127.0.0.1. start|stop|url. Port: JIVA_DASH_PORT pins it; else the
# last one (.jiva/dash/port, kept across stop) if still free, else a random high port (bookmarks survive restarts).
# Web root .jiva/dash/www holds symlinks only (index.html, dash{,-panels}.js, dash{,-parts}.css, phone.{html,css,js}, fonts/*.woff2,
# state.json, snapshot.json, pack.json, avatars/); comb.log, handoff/,
# tasks/, claims/ stay unreachable; pid/port live one level up. API in core/dash-api.py, computed per GET: /flags (name, age,
# first/last line), /asks (open.jsonl: id, class, text, age, protected), /lease (fresh|stale|none + age, as core/lease.sh),
# /comb ({last: per-session last comb line {name,ts,age,verb,text}, tail: last 20, quiet: [names]}),
# /alerts (last 20 notify.log lines `<epoch> <text>` as {ts, age, text}, newest first), /commits, /commit/<sha>, /history[/summary].
# Host header allowlisted in dash-api.py (DNS rebinding); JIVA_DASH_HOSTS="name[:port] …" adds e.g. a tailscale serve name.
set -euo pipefail
# shellcheck source=core/lib.sh
source "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")/lib.sh"
D="$J/dash"; WWW="$D/www"

running() { [[ -s $D/pid ]] && kill -0 "$(cat "$D/pid")" 2>/dev/null; }
url() { echo "http://127.0.0.1:$(cat "$D/port")/"; }

start() {
  running && { url; return; }
  mkdir -p "$WWW"; find "$WWW" -mindepth 1 -delete
  ln -s "$JIVA_HOME/core/dash.html" "$WWW/index.html"; ln -s "$JIVA_HOME/core/dash.js" "$WWW/dash.js"
  local f; for f in dash-panels.js dash-commits.js dash-history.js dash.css dash-parts.css phone.html phone.css phone.js; do ln -s "$JIVA_HOME/core/$f" "$WWW/$f"; done
  mkdir "$WWW/fonts"; for f in "$JIVA_HOME"/site/src/fonts/*.woff2; do ln -s "$f" "$WWW/fonts/"; done   # woff2 only, no OFL txt
  ln -s "$J/state.json" "$WWW/state.json"; ln -s "$JIVA_HOME/packs/default/pack.json" "$WWW/pack.json"
  ln -s "$JIVA_HOME/packs/default/avatars" "$WWW/avatars"
  ln -s "$J/snapshot/snapshot.json" "$WWW/snapshot.json"   # tier-2 phone feed (core/snapshot.sh); dangles until `just snapshot`
  local port pid prot prev; prev="$(cat "$D/port" 2>/dev/null || true)"; [[ $prev =~ ^[0-9]+$ ]] || prev=""
  prot="$(sed -n 's/^ASK_PROTECTED="\(.*\)"$/\1/p' "$JIVA_HOME/core/asks.sh")"   # the one class list
  for i in 1 2 3 4 5 6; do   # try 1 = the sticky port (bind fails if taken → re-roll)
    port="${JIVA_DASH_PORT:-$( ((i == 1)) && [[ -n $prev ]] && echo "$prev" || shuf -i 20000-60000 -n 1)}"
    DJ="$J" DWWW="$WWW" DPROT="$prot" DTTL="${JIVA_LEASE_TTL:-90}" DQUIET="${JIVA_QUIET:-40000}" DTARGET="$TARGET" DHOSTS="${JIVA_DASH_HOSTS:-}" \
      setsid python3 -I "$JIVA_HOME/core/dash-api.py" "$port" >/dev/null 2>&1 < /dev/null &
    pid=$!; sleep 0.5
    kill -0 "$pid" 2>/dev/null && { echo "$pid" > "$D/pid"; echo "$port" > "$D/port"; url; return; }
  done
  echo "dash: could not bind a port" >&2; return 1
}

stop() {
  running && kill "$(cat "$D/pid")" && echo "dash stopped" || echo "dash not running"
  rm -f "$D/pid"   # port stays: the next start reuses it if free
}

case "${1:-start}" in
  start|stop) "${1:-start}" ;;
  url) running && url || { echo "dash not running" >&2; exit 1; } ;;
  *) echo "usage: dash.sh start|stop|url" >&2; exit 2 ;;
esac
