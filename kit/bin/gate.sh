#!/usr/bin/env bash
# gate — anything that needs the keeper becomes ONE runnable line ending in a hard gate, so it fails loudly.
# Cells propose rows; ONLY the keeper runs them. A wrong row gets a corrected new row, never an edit.
#   gate.sh add "<one line>" [why]   linted: one line, ends `… && echo X-OK || { echo X-MISSING; exit 1; }`,
#                                     no $VAR inside a single-quoted sed/awk program (never expands: silent no-op)
#   gate.sh list                      every row + status (pending | ok | fail <rc>)
#   gate.sh run                       what would run (pending + failed rows)
#   gate.sh run go <id…>              keeper only (refused inside a cell): run exactly these, in order, stop at a fail
#   gate.sh result <id> [n]           status + last n output lines; exit 0 ok, 1 fail, 2 pending
# Rows: .hive/state/gate/rows.tsv (id, from, why, cmd) · output <id>.out · exit code <id>.rc
set -uo pipefail
ROOT="${FLEET_ROOT:-$(git rev-parse --show-toplevel)}"; G="$ROOT/.hive/state/gate"; R="$G/rows.tsv"
mkdir -p "$G"; touch "$R"
die() { echo "gate: $*" >&2; exit 1; }
row() { [[ ${1:-} =~ ^g[0-9a-f]{6}$ ]] && awk -F'\t' -v id="$1" '$1 == id' "$R" | tail -1; }
st() { if [[ ! -e $G/$1.rc ]]; then echo pending; elif [[ $(cat "$G/$1.rc") == 0 ]]; then echo ok; else echo "fail $(cat "$G/$1.rc")"; fi; }

lint() { # line → one stderr line per problem; 1 if any
  local c=$1 bad=0 q
  [[ $c != *$'\n'* && -n ${c//[[:space:]]/} ]] || { echo "gate lint: a row is exactly ONE non-empty shell line" >&2; bad=1; }
  [[ $c != *$'\t'* ]] || { echo "gate lint: no tabs in a row" >&2; bad=1; }
  if ! grep -qE '[A-Z0-9_]+-OK' <<<"$c" || ! grep -qE '[A-Z0-9_]+-MISSING' <<<"$c" ||
     ! grep -qE '(exit [1-9][0-9]*|false)[[:space:];})]*$' <<<"$c"; then
    echo "gate lint: no hard gate at the end — finish with … && echo X-OK || { echo X-MISSING; exit 1; }" >&2; bad=1
  fi
  q="$(grep -oE "(sed|awk)[^|;&']*'[^']*'" <<<"$c" | grep -oE '\$\{?[A-Za-z_][A-Za-z0-9_]*' | grep -vxE '\$\{?(NF|NR|FNR)' | head -1)" || true
  [[ -z $q ]] || { echo "gate lint: $q inside a single-quoted sed/awk program never expands — use \"…\" or awk -v" >&2; bad=1; }
  return $bad
}

add() {
  local c=${1:-} why=${2:-row} id
  lint "$c" || die "row refused — write a corrected one"
  id="g$(od -An -N3 -tx1 /dev/urandom | tr -d ' \n')"
  { flock 8; printf '%s\t%s\t%s\t%s\n' "$id" "${FLEET_NAME:-desk}" "${why//$'\t'/ }" "$c" >> "$R"; } 8> "$G/lock"
  echo "gate $id queued — the keeper runs \`just hive gate-run go $id\`; check it with \`just hive gate-result $id\`"
}

list() { # [open]
  local id from why cmd s n=0
  while IFS=$'\t' read -r id from why cmd; do
    s=$(st "$id"); [[ ${1:-} != open || $s != ok ]] || continue; n=$((n + 1))
    printf '%s [%s] %s: %s\n    $ %s\n' "$id" "$s" "$from" "$why" "$cmd"
  done < "$R"
  (( n )) || echo "(no ${1:+open }gate rows)"
}

go() {
  [[ -z ${FLEET_ROLE:-} ]] || die "go is keeper-only (this is hive cell ${FLEET_NAME:-?}) — ask the keeper"
  (($#)) || die "run go <id…> — \`gate.sh run\` shows the plan first"
  local id r rc
  for id; do r=$(row "$id"); [[ -n $r ]] || die "no row '$id'"; [[ $(st "$id") != ok ]] || die "$id already ran ok"; done
  for id; do
    r=$(row "$id" | cut -f4-); echo "== $id \$ $r"
    (cd "$ROOT" && bash -c "$r") 2>&1 | tee "$G/$id.out"; rc=${PIPESTATUS[0]}
    echo "$rc" > "$G/$id.rc"; echo "== $id rc=$rc"
    (( rc == 0 )) || die "$id failed rc=$rc — stopped, later rows not run"
  done
}

result() {
  local s; [[ -n $(row "${1:-}") ]] || die "no row '${1:-}'"
  s=$(st "$1"); echo "gate $1: $s"
  [[ -e $G/$1.out ]] && tail -n "${2:-15}" "$G/$1.out"
  case $s in ok) return 0 ;; fail*) return 1 ;; *) return 2 ;; esac
}

[[ ${BASH_SOURCE[0]} == "$0" ]] || return 0
cmd=${1:-list}; shift || true
case $cmd in
  add|list|result) "$cmd" "$@" ;;
  run) if [[ ${1:-} == go ]]; then shift; go "$@"; else list open; fi ;;
  lint) lint "${1:-}" && echo "gate lint: ok" ;;
  *) echo "usage: gate.sh add|list|run [go <id…>]|result|lint …" >&2; exit 2 ;;
esac
