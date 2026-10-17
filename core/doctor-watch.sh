#!/usr/bin/env bash
# doctor-watch — `jiva watch` piped (non-tty) against a scratch TARGET in /tmp: seed state.json (2 sessions, q5h 90%),
# a decision + a protected ask, one flag and a board; assert the one frame holds each item and exits 0.
# ALERTS = last 3 notify.log lines, ALERT word when < 5 min. Session rows: last board line (· Nm ago verb text), "quiet" from a burn marker,
# clipped to COLUMNS. Dash URL on line 1 (stub pid/port), "dash: down" on a dead pid. Then no state.json → "runtime down". Prints ok/FAIL; exit 1 on any FAIL.
set -uo pipefail
H="$(cd "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")/.." && pwd)"
S="$(mktemp -d /tmp/jiva-doctor-XXXXXX)"; J="$S/.jiva"
trap 'rm -rf "$S"' EXIT
bad=0
ok() { printf 'ok    watch %s\n' "$1"; }
no() { printf 'FAIL  watch %s\n' "$1"; bad=1; }
has() { if grep -qF -- "$2" <<<"$F"; then ok "$1"; else no "$1 (missing: $2)"; fi; }

mkdir -p "$S/bin"; printf '#!/bin/sh\nexit 0\n' > "$S/bin/tmux"; chmod +x "$S/bin/tmux"; export PATH="$S/bin:$PATH"   # tmux "up"
now=$(date +%s); mkdir -p "$J/flags" "$J/asks"
echo storm > "$J/flags/storm"
jq -nc --argjson ts $((now - 180)) '{id:"aa11", ts:$ts, from:"w1", class:"decision", q:"pick a port", opts:[], default:"1", deadline:0}' \
  > "$J/asks/open.jsonl"
jq -nc --argjson ts "$now" '{id:"bb22", ts:$ts, from:"w2", class:"deploy", q:"ship it?", opts:[], default:"no", deadline:0}' \
  >> "$J/asks/open.jsonl"
jq -nc --argjson ts "$now" '{ts:$ts, lease:"stale", live:2, flags:1, asks:2, tok:52000, q5h:90, q7d:10, sessions:[
  {name:"boss", status:"busy", waiting:null, tok:40000, pct:20}, {name:"w7", status:"idle", waiting:"perm", tok:12000, pct:6},
  {name:"w8", status:"busy", waiting:null, tok:3000, pct:1, soul:{name:"Ash", slot:1, color:"#e75555"}}]}' \
  > "$J/state.json"
{ echo "01:00 w8     shipped: soul row"; for i in $(seq 1 12); do echo "01:0$((i % 10)) w7     board line $i"; done; } > "$J/board.log"
printf '%s old alert\n%s mid alert\n%s w3 parked\n%s newest alert\n' $((now - 900)) $((now - 600)) $((now - 400)) \
  $((now - 60)) > "$J/notify.log"   # 4 lines → only the last 3 shown, newest first
mkdir -p "$J/dash"; echo $$ > "$J/dash/pid"; echo 4242 > "$J/dash/port"   # stub dash: our own pid is alive
mkdir -p "$J/nudged"; echo "0 -5000" > "$J/nudged/boss.last"; echo "12 11000" > "$J/nudged/w7.last"   # boss +45k → quiet

F="$(JIVA_TARGET="$S" LINES=10 "$H/core/watch.sh" < /dev/null)"; rc=$?
[[ $rc == 0 ]] && ok "piped exits 0" || no "piped exit $rc"
has "line 1 = status summary" "2 live · 1 flag · 52k · lease stale"
has "quota on line 1" "q5h 90%"
[[ $(head -1 <<<"$F") == *"lease stale · dash http://127.0.0.1:4242/ · q5h"* ]] && ok "dash URL on line 1 when pid alive" ||
  no "dash up: $(head -1 <<<"$F")"
[[ $(JIVA_TARGET="$S" "$H/core/status.sh" | head -1) == *"· dash http://127.0.0.1:4242/" ]] && ok "status shows the dash URL" ||
  no "status dash: $(JIVA_TARGET="$S" "$H/core/status.sh" | head -1)"
has "alarm words (no colour-only meaning)" "LEASE-STALE PROTECTED-ASK QUOTA≥85%"
grep -q $'\e' <<<"$F" && no "no escape codes when piped" || ok "no escape codes when piped"
has "session row boss" "boss"; has "session row w7 + waiting" "perm"
has "FLAGS line + hint" "FLAGS: storm   (clear: rm .jiva/flags/<name>)"
has "OPEN ASKS header + answer hint" "OPEN ASKS (2) — jiva answer <id> [text]"
has "decision ask row" "aa11  decision  3m  w1: pick a port"
has "protected ask marked [!]" "[!] bb22  deploy"
has "ALERTS = last 3, newest first, with age" "ALERTS: 1m ago newest alert · 6m ago w3 parked · 10m ago mid alert"
grep -q 'old alert' <<<"$F" && no "ALERTS shows more than 3" || ok "ALERTS keeps only 3"
grep -q '!!.* ALERT' <<<"$(head -1 <<<"$F")" && ok "ALERT alarm word" || no "no ALERT word"
row() { grep -E "^  $1 " <<<"$F"; }
grep -qE ' · [0-9]+m ago board line 12$' <<<"$(row w7)" && ok "w7 row ends with its last board line" || no "w7 row: $(row w7)"
[[ $(row boss) == *"quiet  · (no report yet)" ]] && ok "boss: quiet (+45k) + no report yet" || no "boss row: $(row boss)"
[[ $(grep -E '^  Ash · w8 ' <<<"$F") == *"busy"*"m ago shipped soul row" ]] && ok "soul label row 'Ash · w8' keeps its board line" ||
  no "w8 soul row: $(grep -E 'w8' <<<"$F" | head -1)"
grep -qE '^  Ash · w8[[:space:]]+busy' <<<"$(JIVA_TARGET="$S" "$H/core/status.sh")" && ok "status row 'Ash · w8'" || no "status has no soul row"
[[ $(row w7) != *quiet* ]] && ok "w7 not quiet (+1k)" || no "w7 marked quiet"
L="$(JIVA_TARGET="$S" COLUMNS=50 "$H/core/watch.sh" < /dev/null | grep -E '^  w7 ')"
(( ${#L} <= 50 )) && ok "rows clipped to COLUMNS (no wrap)" || no "row is ${#L} > 50 chars"
has "board tail (min 5 lines)" "board line 12"
[[ $(grep -c '^01:.*board line' <<<"$F") == 5 ]] && ok "board N clamps to 5 on a short terminal" ||
  no "board N on LINES=10 is $(grep -c '^01:.*board line' <<<"$F"), want 5"
[[ $(head -1 <<<"$F") == *"lease stale"* ]] && ok "status is the first line" || no "status not first line"

echo "$((now - 400)) stale one" > "$J/notify.log"
F="$(JIVA_TARGET="$S" "$H/core/watch.sh" < /dev/null)"
has "old alert still listed" "ALERTS: 6m ago stale one"; [[ $(head -1 <<<"$F") != *ALERT* ]] && ok "no ALERT word at ≥5 min" || no "ALERT word on a 6m alert"
sleep 0 & wait $!; echo $! > "$J/dash/pid"   # a pid that just exited
[[ $(JIVA_TARGET="$S" "$H/core/status.sh" | head -1) == *"· dash: down (jiva dash start)" ]] && ok "status: dash down on dead pid" ||
  no "status dash down: $(JIVA_TARGET="$S" "$H/core/status.sh" | head -1)"
rm "$J/state.json" "$J/asks/open.jsonl" "$J/flags/storm" "$J/notify.log"
F="$(JIVA_TARGET="$S" "$H/core/watch.sh" < /dev/null)"; rc=$?
[[ $rc == 0 ]] && ok "no state.json still exits 0" || no "no state.json exit $rc"
has "runtime down + alarm" "RUNTIME-DOWN"
has "watch: dash down when pid dead" "dash: down (jiva dash start)"
grep -qE 'FLAGS|OPEN ASKS|ALERTS' <<<"$F" && no "empty flags/asks/alerts hidden" || ok "empty flags/asks/alerts hidden"
exit $bad
