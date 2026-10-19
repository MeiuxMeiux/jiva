# shellcheck shell=bash
# asks — typed asks for the desk (docs/history/PLAN.md "Asks"). Sourced by core/verbs.sh and core/watchdog.sh.
#   .jiva/asks/open.jsonl      one JSON line per open ask {id,ts,from,class,q,opts[],default,deadline}
#   .jiva/asks/answered.jsonl  closed asks, + {answer, ats, by}
#   .jiva/asks/digest          ts of the last desk digest (absent ⇔ no open asks at the last tick)
# Count is `wc -l` of open.jsonl — zero tokens. $JIVA_SAY overrides delivery (doctor stubs it).
A="$J/asks"; mkdir -p "$A"
declare -F hist >/dev/null || source "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")/history.sh"  # hist (notes/history.md)
# the ONE list of ask classes. Only `decision` may auto-apply its default at the deadline; every
# protected class stays open past it and is only re-surfaced by the digest (a keeper must answer).
ASK_PROTECTED="permission deploy spend destructive sudo remote license"
ask_log() { board_log "${JIVA_NAME:-desk}" "$*"; }
ask_say() { # name text — best effort; a missing window never breaks the caller
  if [[ -n ${JIVA_SAY:-} ]]; then "$JIVA_SAY" "$1" "$2"; else "$JIVA_HOME/core/jiva.sh" say "$1" "$2"; fi \
    >/dev/null 2>&1 || true
}
ask_count() { [[ -s $A/open.jsonl ]] && wc -l < "$A/open.jsonl" || echo 0; }

ask_new() { # q opts default [class] — opts split on , or |; class defaults to decision
  local id now c=${4:-decision}
  [[ " decision $ASK_PROTECTED " == *" $c "* ]] || { echo "ask: class $c not in: decision $ASK_PROTECTED" >&2; return 1; }
  id="$(od -An -N3 -tx1 /dev/urandom | tr -d ' \n')"; now=$(date +%s)
  jq -nc --arg id "$id" --argjson ts "$now" --arg from "${JIVA_NAME:-desk}" --arg c "$c" --arg q "$1" --arg o "${2:-}" \
    --arg d "${3:-}" --argjson dl $((now + ${JIVA_ASK_TTL:-1800})) \
    '{id: $id, ts: $ts, from: $from, class: $c, q: $q, opts: ($o | split("[,|]"; null) | map(gsub("^ +| +$"; "")) | map(select(. != ""))),
      default: $d, deadline: $dl}' | { flock 8; cat >> "$A/open.jsonl"; } 8> "$A/lock"
  ask_log "ask $id: $1"; hist ask id="$id" class="$c"; echo "ask $id queued for the desk"
}

ask_answer() { # id [text] [by] — empty text applies the default; moves the ask to answered.jsonl
  local id=$1 text=${2:-} by=${3:-${JIVA_NAME:-desk}} row from ans
  exec 8> "$A/lock"; flock 8
  row="$(jq -c --arg id "$id" 'select(.id == $id)' "$A/open.jsonl" 2>/dev/null)"
  [[ -n $row ]] || { exec 8>&-; echo "answer: no open ask $id" >&2; return 1; }
  [[ -n $text ]] || text="$(jq -r '.default' <<<"$row")"
  jq -c --arg a "$text" --arg by "$by" --argjson now "$(date +%s)" '. + {answer: $a, ats: $now, by: $by}' \
    <<<"$row" >> "$A/answered.jsonl"
  jq -c --arg id "$id" 'select(.id != $id)' "$A/open.jsonl" > "$A/open.tmp" && mv "$A/open.tmp" "$A/open.jsonl"
  exec 8>&-
  from="$(jq -r '.from' <<<"$row")"; ans="JIVA answer $id: $text"
  ask_say "$from" "$ans"
  if [[ $by == expired ]]; then ask_log "ask $id expired→default: $text"; hist expire id="$id" class="$(jq -r '.class // "decision"' <<<"$row")"
  else ask_log "answer $id: $text"; hist answer id="$id" by="$by"; fi
  echo "$ans → $from"
}

ask_inbox() { # one line per open ask: id, age, from, q, default, deadline
  [[ -s $A/open.jsonl ]] || return 0
  echo "-- open asks ($(ask_count)) — jiva answer <id> [text]; no text = default"
  jq -r --argjson now "$(date +%s)" '"\(.id)  \(($now - .ts) / 60 | floor)m  \(.from) [\(.class // "decision")]: \(.q)" +
    (if (.opts | length) > 0 then "  [\(.opts | join("|"))]" else "" end) +
    "  default: \(.default)  deadline: \(.deadline | strflocaltime("%H:%M"))"' "$A/open.jsonl"
}

ask_expire() { # past-deadline `decision` asks get their default, once (answering removes them); others wait
  local id
  [[ -s $A/open.jsonl ]] || return 0
  for id in $(jq -r --argjson now "$(date +%s)" 'select($now > .deadline and (.class // "decision") == "decision") | .id' "$A/open.jsonl"); do
    ask_answer "$id" "" expired >/dev/null || true
  done
}

ask_digest() { # ONE say to the desk on 0 → ≥1 open asks, then at most every JIVA_DIGEST seconds
  local n now last desk
  n=$(ask_count); now=$(date +%s)
  (( n > 0 )) || { rm -f "$A/digest"; return 0; }
  last=$(cat "$A/digest" 2>/dev/null || echo 0); [[ $last =~ ^[0-9]+$ ]] || last=0   # file text never reaches (( ))
  (( now - last >= ${JIVA_DIGEST:-600} )) || return 0
  desk="${JIVA_DESK:-$(grep -lx desk "$J"/launch/* 2>/dev/null | head -1 | xargs -r basename)}"
  echo "$now" > "$A/digest"
  ask_say "${desk:-desk}" "JIVA: $n open ask$( ((n > 1)) && echo s) — \`jiva inbox\`"
}
