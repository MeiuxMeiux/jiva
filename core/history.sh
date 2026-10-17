#!/usr/bin/env bash
# shellcheck shell=bash
# history — cumulative, append-only fleet history (notes/history.md has every kind + field). Sourced:
#   hist <kind> [k=v …]  one JSON line {ts, kind, who, k: v…} → $J/history.jsonl. who = $JIVA_NAME (desk).
#                        Values: an integer/decimal stays a number (except label keys id sha name by class
#                        st why trip, always strings: a hex id can be all digits), else a string with control
#                        chars flattened and cut to 80 chars; keys must match [a-z][a-z0-9_]* (others
#                        dropped, ts/kind/who reserved). Never prompts, card bodies, diffs or file text.
#   hist_tok <merged>    watchdog: {kind:"tok", tok, s:{name: tok}, q5h, q7d} at most every JIVA_HIST_TOK secs (300)
# Never fails the caller (set -e safe), never blocks: appends under `flock -w 1`, skipped on timeout.
# Lines are never rewritten. Run directly: `history.sh [n]` (= `jiva history [n]`) prints the last n (20).
if [[ -z ${J:-} ]]; then
  # shellcheck source=core/lib.sh
  source "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")/lib.sh"
fi

hist_append() { # one compact JSON line → history.jsonl under the lock; errors swallowed
  [[ -n $1 && $1 != *$'\n'* ]] || return 0
  {
    mkdir -p "$J" && { flock -w 1 7 && printf '%s\n' "$1" >> "$J/history.jsonl"; } 7>> "$J/history.lock"
  } 2>/dev/null || true
  return 0
}

hist() { # kind [k=v …]
  local line
  line="$(jq -nc --arg kind "${1:-?}" --arg who "${JIVA_NAME:-desk}" --argjson ts "$(date +%s)" '
    def lbl: tostring | gsub("[[:cntrl:]]"; " ") | .[0:80];
    ([$ARGS.positional[] | capture("^(?<k>[^=]*)=(?<v>[\\s\\S]*)$")
      | select(.k | test("^[a-z][a-z0-9_]{0,23}$")) | select(.k | IN("ts", "kind", "who") | not)
      | {(.k): (if (.v | test("^-?[0-9]{1,15}(\\.[0-9]{1,6})?$")) and (.k | IN("id", "sha", "name", "by", "class", "st", "why", "trip") | not)
        then .v | tonumber else .v | lbl end)}]
     | add // {}) as $kv
    | {ts: $ts, kind: ($kind | lbl), who: ($who | lbl)} + $kv' --args "${@:2}" 2>/dev/null)" || return 0
  hist_append "$line"
}

hist_tok() { # merged state.json text → rate-limited token + quota snapshot
  local now last f="$J/history.tok"; now=$(date +%s)
  last=$(cat "$f" 2>/dev/null || echo 0); [[ $last =~ ^[0-9]+$ ]] || last=0
  (( now - last >= ${JIVA_HIST_TOK:-300} )) || return 0
  { echo "$now" > "$f"; } 2>/dev/null || true
  hist_append "$(jq -c --argjson ts "$now" '{ts: $ts, kind: "tok", who: "watchdog", tok: (.tok // 0),
    s: ([.sessions[]? | {(.name | tostring | .[0:24]): (.tok // 0)}] | add // {}),
    q5h: (.q5h // null), q7d: (.q7d // null)}' <<<"$1" 2>/dev/null)"
}

[[ ${BASH_SOURCE[0]} == "$0" ]] || return 0
n="${1:-20}"; [[ $n =~ ^[0-9]+$ ]] || { echo "usage: jiva history [n]" >&2; exit 1; }
tail -n "$n" "$J/history.jsonl" 2>/dev/null || echo "(no history yet)"
