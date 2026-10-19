#!/usr/bin/env bash
# doctor-hive — lane-A tactics as tests, all in a scratch TARGET (notes/hive.md):
#   gate rows: lint refuses ungated / quoted-$VAR rows · go refused inside a cell · deps enforced · rc + out saved ·
#             fix supersedes · result exit codes   ·   card lint: missing fields rejected, Claim:/Done-check: accepted
#   desk digest: silent when unchanged, one line on change   ·   profile: solo/duo/full lines + bad input refused
#   lean launch: cmdline carries --strict-mcp-config + --disallowedTools, JIVA_LEAN=0 drops them
set -uo pipefail
H="$(cd "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")/.." && pwd)"; bad=0
ok() { printf 'ok    hive %s\n' "$1"; }
no() { printf 'FAIL  hive %s\n' "$1"; bad=1; }
t() { local l=$1; shift; if "$@" >/dev/null 2>&1; then ok "$l"; else no "$l"; fi; }
S=/tmp/jiva-scratch/doctor-hive; rm -rf "${S:?}"; mkdir -p "$S" && git -C "$S" init -q
export JIVA_TARGET="$S" JIVA_NAME=desk JIVA_ROLE='' JIVA_NOTIFY=off; GK="$H/core/gate.sh"
last() { jq -r .id "$S/.jiva/gate/rows.jsonl" | tail -1; }

t "gate: ungated row refused" bash -c "! '$GK' add 'echo hi'"
t "gate: \$VAR in single-quoted sed refused" bash -c "! '$GK' add \"sed -i 's/a/\\\$FOO/' f && echo F-OK || { echo F-MISSING; exit 1; }\""
t "gate: two-line row refused" bash -c "! '$GK' add \$'true\\necho X-OK || exit 1'"
t "gate: gated row accepted" "$GK" add "true && echo A-OK || { echo A-MISSING; exit 1; }" a; a=$(last)
t "gate: dep row accepted" "$GK" add "false && echo B-OK || { echo B-MISSING; exit 1; }" b "$a"; b=$(last)
t "gate: go refused inside a cell" bash -c "! JIVA_ROLE=worker '$GK' go $a"
t "gate: dep not ok → batch stops" bash -c "! '$GK' go $b && [[ ! -e '$S/.jiva/gate/$b.rc' ]]"
t "gate: failed row stops batch, rc saved" bash -c "! '$GK' go $a $b && [[ \$(cat '$S/.jiva/gate/$b.rc') == 1 && \$(cat '$S/.jiva/gate/$a.rc') == 0 ]]"
t "gate: output saved per row" grep -q B-MISSING "$S/.jiva/gate/$b.out"
t "gate: result exit 0 ok / 1 fail" bash -c "'$GK' result $a && ! '$GK' result $b"
t "gate: ok row never re-runs" bash -c "! '$GK' go $a"
t "gate: fix supersedes the old row" "$GK" fix "$b" "true && echo B-OK || { echo B-MISSING; exit 1; }" b2; c=$(last)
t "gate: superseded row refused" bash -c "! '$GK' go $b"
t "gate: result 2 while not run" bash -c "'$GK' result $c; [[ \$? == 2 ]]"

printf 'Area: core\nGoal: x\n' > "$S/c1.md"; printf 'Area: core\nDo it. Claim: core/x\nDone-check: y\n' > "$S/c2.md"
t "card: missing Owned paths/Done-when rejected" bash -c "! '$H/core/card.sh' '$S/c1.md'"
t "card: Claim:/Done-check: accepted" "$H/core/card.sh" "$S/c2.md"

D="$H/core/digest.sh"; "$D" >/dev/null
t "digest: silent when nothing changed" bash -c "[[ -z \$('$D') ]]"
mkdir -p "$S/.jiva/flags"; echo x > "$S/.jiva/flags/w1"
t "digest: one line when a flag appears" bash -c "[[ \$('$D' | grep -c 'flags: w1') == 1 ]]"
t "digest: silent again" bash -c "[[ -z \$('$D') ]]"

P="$H/core/profile.sh"
t "profile: solo = no queen, 1 worker" bash -c "[[ \$('$P' solo | head -1) == '0 0 1 solo' ]]"
t "profile: N = duo:N" bash -c "[[ \$('$P' 3 | head -1) == '1 0 3 duo' ]]"
t "profile: full = queen + loop" bash -c "[[ \$('$P' full:1 | head -1) == '1 1 1 full' ]]"
t "profile: auto prints why" bash -c "'$P' | grep -q 'auto →'"
t "profile: bad input refused" bash -c "! '$P' bogus && ! '$P' solo:2"

l="$(sed -n '/^lean() {/,/^cmdline()/p' "$H/core/jiva.sh" | sed '$d')"
t "lean: cells launch --strict-mcp-config + --disallowedTools" bash -c "$l; [[ \$(lean) == *--strict-mcp-config*--disallowedTools*Artifact* ]]"
t "lean: JIVA_LEAN=0 opts out" bash -c "$l; [[ -z \$(JIVA_LEAN=0 lean) ]]"
rm -rf "${S:?}"
exit $bad
