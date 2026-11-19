#!/usr/bin/env bash
# snapshot — `snapshot [out-dir]`: tier-2 phone view feed. Writes <out-dir>/snapshot.json (default .jiva/snapshot/),
# atomically, through an explicit jq ALLOWLIST — every string is re-filtered to [A-Za-z0-9_.-] ≤24 chars, so no path,
# sha, branch, card/ask/comb text or env can leak. Kept: generated ts, live/flags/asks counts, quota %, lease state+age,
# sessions {name, slot, color, status, tok, verb} (verb = the word only of that session's last comb line; slot/color =
# state.json sessions[].soul, the watchdog's souls.json binding — wN→N only when .soul is absent; name stays the address),
# flags {name, age}, asks {id, class, age} (never the question). Read-only consumer: core/phone.html via the dash.
set -euo pipefail
# shellcheck source=core/lib.sh
source "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")/lib.sh"
OUT="${1:-$J/snapshot}"; mkdir -p "$OUT"; now=$(date +%s)
TTL="${JIVA_LEASE_TTL:-90}"

state="$(jq -c . "$J/state.json" 2>/dev/null || echo '{}')"
pack="$(jq -c . "$JIVA_HOME/packs/default/pack.json" 2>/dev/null || echo '{}')"
shopt -s nullglob
flags="$(for f in "$J"/flags/*; do [[ -f $f ]] && printf '%s %s\n' "$(basename "$f")" "$((now - $(stat -c %Y "$f")))" || true; done |
  jq -Rsc '[split("\n")[] | select(length > 0) | split(" ") | {name: .[0], age: (.[1] | tonumber)}]')"
asks="$(jq -sc '.' "$J/asks/open.jsonl" 2>/dev/null || echo '[]')"
lease="$(read -r ts _ < "$J/lease/queen" 2>/dev/null && [[ $ts =~ ^[0-9]+$ ]] &&
  jq -nc --argjson a $((now - ts)) --argjson t "$TTL" '{state: (if $a > 3 * $t then "stale" else "fresh" end), age: $a}' ||
  echo '{"state":"none","age":null}')"
verbs="$(awk 'NF >= 3 { v[$2] = $3 } END { for (n in v) print n, v[n] }' "$J/comb.log" 2>/dev/null |
  jq -Rsc '[split("\n")[] | select(length > 0) | split(" ") | {key: .[0], value: .[1]}] | from_entries')"

jq -n --argjson now "$now" --argjson s "$state" --argjson p "$pack" --argjson f "$flags" --argjson a "$asks" \
  --argjson l "$lease" --argjson v "$verbs" '
  def safe: tostring | gsub("[^A-Za-z0-9_.-]"; "") | .[0:24];
  def word: tostring | gsub("[^a-z-]"; "") | .[0:16];
  def num: if type == "number" then . else null end;
  def hex: tostring | if test("^#[0-9a-fA-F]{6}$") then . else null end;
  def slot: (.name | tostring) as $n | if (.soul | type) == "object" then (.soul.slot | num)
    elif $n == "queen" then 0 elif ($n | test("^w[0-9]{1,3}$")) then ($n[1:] | tonumber) else null end;
  def color($k): if $k == 0 then ($p.queen.color // null | hex)
    elif $k == null then null else ([$p.slots[]? | select(.slot == $k) | .color][0] // null | hex) end;
  ($s.sessions // []) as $ss | {
    ts: $now, state_ts: ($s.ts | num), live: ($s.live | num),
    quota: {q5h: ($s.q5h | num), q7d: ($s.q7d | num)},
    lease: {state: ($l.state | safe), age: ($l.age | num)},
    sessions: [$ss[] | slot as $k | {name: (.name | safe), slot: $k, color: ((.soul.color? // null | hex) // color($k)),
      status: (.status | safe), tok: (.tok | num), verb: ($v[.name | tostring] // "" | word)}],
    flags: [$f[] | {name: (.name | safe), age: (.age | num)}],
    asks: [$a[] | {id: (.id | safe), class: (.class | safe), age: (if (.ts | type) == "number" then $now - .ts else null end)}]
  }' > "$OUT/.snapshot.json.tmp"
mv "$OUT/.snapshot.json.tmp" "$OUT/snapshot.json"
echo "$OUT/snapshot.json"
