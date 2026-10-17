#!/usr/bin/env bash
# gate — one-liner rows a seat proposes and ONLY the human runs (notes/fleet.md). Rows are never edited:
# a wrong row gets a corrected NEW row (`fix`), the old one is marked superseded. Decision/send/spend
# choices are asks (`jiva ask … <class>`), never rows: gate runs kind `oneliner` only.
#   gate.sh add "<one shell line>" [why] [deps,…]   linted at creation: hard gate at the end, no $VAR in '…' sed/awk
#   gate.sh fix <old-id> "<line>" [why] [deps,…]    corrected new row; <old-id> → superseded
#   gate.sh plan [all]                               what would run (open + failed rows; `all` = every row)
#   gate.sh go <id…>                                 human only: run exactly these, in order; deps must be ok;
#                                                    stops at the first failure; output → .jiva/gate/<id>.out, rc → <id>.rc
#   gate.sh result <id> [n]                          asker's check: status + last n output lines; exit 0 ok, 1 fail, 2 open
# .jiva/gate/rows.jsonl {id,ts,from,kind,cmd,why,deps[],sup}  ·  <id>.sup = the id that replaced it.
set -uo pipefail
# shellcheck source=core/lib.sh
source "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")/lib.sh"
JK="$J/gate"; R="$JK/rows.jsonl"; mkdir -p "$JK"
die() { echo "gate: $*" >&2; exit 1; }
row() { [[ $1 =~ ^g[0-9a-f]{4,8}$ ]] && jq -c --arg id "$1" 'select(.id == $id)' "$R" 2>/dev/null | tail -1; }
st() { # id → pending | ok | fail <rc> | superseded
  if [[ -e $JK/$1.sup ]]; then echo superseded
  elif [[ ! -e $JK/$1.rc ]]; then echo pending
  elif [[ $(cat "$JK/$1.rc") == 0 ]]; then echo ok
  else echo "fail $(cat "$JK/$1.rc")"; fi
}

lint() { # line → one stderr line per problem; 1 if any
  local c=$1 bad=0 q
  [[ $c != *$'\n'* && -n ${c//[[:space:]]/} ]] || { echo "gate lint: a row is exactly ONE non-empty shell line" >&2; bad=1; }
  if ! grep -qE '[A-Z0-9_]+-(OK|MISSING|FAIL|BAD)' <<<"$c" || ! grep -qE '(exit [1-9][0-9]*|false)[[:space:];})]*$' <<<"$c"; then
    echo "gate lint: no hard gate at the end — finish with e.g. … && echo X-OK || { echo X-MISSING; exit 1; }" >&2; bad=1
  fi
  q="$(grep -oE "(sed|awk)[^|;&']*'[^']*'" <<<"$c" | grep -oE '\$\{?[A-Z_][A-Z0-9_]*' | grep -vxE '\$(NF|NR|FNR)' | head -1)"
  [[ -z $q ]] || { echo "gate lint: $q inside a single-quoted sed/awk program never expands (silent no-op) — use \"…\" or awk -v" >&2; bad=1; }
  return $bad
}

NEW=""
add() { # cmd [why] [deps] [supersedes]
  local c=${1:-} why=${2:-} deps=${3:-} d
  lint "$c" || die "row refused — write a corrected one"
  for d in ${deps//,/ }; do [[ -n $(row "$d") ]] || die "dep $d: no such row"; done
  NEW="g$(od -An -N3 -tx1 /dev/urandom | tr -d ' \n')"
  jq -nc --arg id "$NEW" --argjson ts "$(date +%s)" --arg from "${JIVA_NAME:-desk}" --arg c "$c" --arg w "$why" \
    --arg d "$deps" --arg s "${4:-}" '{id: $id, ts: $ts, from: $from, kind: "oneliner", cmd: $c, why: $w,
      deps: ($d | split("[, ]+"; null) | map(select(. != ""))), sup: $s}' | { flock 8; cat >> "$R"; } 8> "$JK/lock"
  board_log "${JIVA_NAME:-desk}" "gate $NEW: ${why:-row}${4:+ (replaces $4)}"
  echo "gate $NEW queued — the human runs \`just gate-run go $NEW\`; check it with \`just gate-result $NEW\`"
}
fix() { # old cmd [why] [deps]
  local old=${1:-}; [[ -n $(row "$old") ]] || die "no row '$old'"
  case "$(st "$old")" in ok) die "$old already ran ok — add a new row instead" ;; superseded) die "$old already superseded by $(cat "$JK/$old.sup")" ;; esac
  add "${2:-}" "${3:-}" "${4:-}" "$old"; echo "$NEW" > "$JK/$old.sup"
}

plan() { # [all]
  local id s n=0
  for id in $(jq -r '.id' "$R" 2>/dev/null); do
    s=$(st "$id"); [[ ${1:-} == all || $s == pending || $s == fail* ]] || continue
    ((n++)) || echo "-- gate rows: the human runs \`just gate-run go <id…>\` (exactly those, in order)"
    jq -r --arg s "$s" '"\(.id) [\($s)] \(.from)\(if (.deps | length) > 0 then " after " + (.deps | join(",")) else "" end): \(.why)\n    $ \(.cmd)"' <<<"$(row "$id")"
  done
  ((n)) || echo "(no open gate rows)"
}

go() { # ids…
  [[ -z ${JIVA_ROLE:-} ]] || die "go is human-only (this is fleet seat ${JIVA_NAME:-?}) — ask the human"
  (($#)) || die "go <id…> — \`just gate-run\` shows the plan first"
  local id r d s rc from
  for id; do   # validate the whole batch before running anything
    r=$(row "$id"); [[ -n $r ]] || die "no row '$id'"
    [[ $(jq -r .kind <<<"$r") == oneliner ]] || die "$id: kind is not oneliner — never self-runs"
    s=$(st "$id"); [[ $s == superseded ]] && die "$id superseded by $(cat "$JK/$id.sup")"; [[ $s == ok ]] && die "$id already ran ok"
  done
  for id; do
    r=$(row "$id")
    for d in $(jq -r '.deps[]' <<<"$r"); do [[ $(st "$d") == ok ]] || die "$id: dep $d is $(st "$d") — stopped, later rows not run"; done
    echo "== $id \$ $(jq -r .cmd <<<"$r")"
    (cd "$TARGET" && bash -c "$(jq -r .cmd <<<"$r")") 2>&1 | tee "$JK/$id.out"; rc=${PIPESTATUS[0]}
    echo "$rc" > "$JK/$id.rc"; echo "== $id rc=$rc (.jiva/gate/$id.out)"
    board_log human "gate $id rc=$rc"; from=$(jq -r .from <<<"$r")
    [[ $from == desk ]] || "$JIVA_HOME/core/jiva.sh" say "$from" "JIVA gate $id: rc=$rc — \`just gate-result $id\`" >/dev/null 2>&1 || true
    (( rc == 0 )) || die "$id failed rc=$rc — stopped, later rows not run"
  done
}

result() { # id [n]
  local s; [[ -n $(row "${1:-}") ]] || die "no row '${1:-}'"
  s=$(st "$1"); echo "gate $1: $s"
  [[ -e $JK/$1.out ]] && tail -n "${2:-15}" "$JK/$1.out"
  case $s in ok) return 0 ;; fail*) return 1 ;; *) return 2 ;; esac
}

[[ ${BASH_SOURCE[0]} == "$0" ]] || return 0
cmd=${1:-plan}; shift || true
case $cmd in
  add|fix|plan|go|result) "$cmd" "$@" ;;
  lint) lint "${1:-}" && echo "gate lint: ok" ;;
  *) echo "usage: gate.sh add|fix|plan|go|result|lint …" >&2; exit 2 ;;
esac
