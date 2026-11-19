#!/usr/bin/env bash
# doctor-history — core/history.sh + every emitter against a scratch TARGET (/tmp/jiva-doctor-*, own git repo,
# stub `claude`, stubbed T/JV/toast — no tmux, no hive): each kind's shape matches notes/history.md, lines
# are append-only across runs, a value with newlines can't inject a line, a 200-char label is cut to 80,
# the tok snapshot is rate-limited, an unwritable J never fails a set -e caller. ok/FAIL; exit 1 on any FAIL.
set -uo pipefail
H="$(cd "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")/.." && pwd)"
S="$(mktemp -d /tmp/jiva-doctor-XXXXXX)"; trap 'rm -rf "$S"' EXIT
export JIVA_TARGET="$S" JIVA_HOOKS=settings JIVA_DRY=1 JIVA_SAY=true JIVA_NOTIFY=off
J="$S/.jiva"; HJ="$J/history.jsonl"; V="$H/core/verbs.sh"; bad=0
ok() { printf 'ok    history %s\n' "$1"; }
no() { printf 'FAIL  history %s\n' "$1"; bad=1; }
git -C "$S" init -q; git -C "$S" -c user.name=d -c user.email=d@d commit -q --allow-empty -m init
mkdir -p "$S/stub" "$J"/{state,launch,rotate}
cat > "$S/stub/claude" <<'SH'
#!/usr/bin/env bash
[[ ${1:-} == agents ]] && jq -nc --arg c "$JIVA_TARGET" '[{name: "w1", cwd: $c, status: "idle", startedAt: ((now - 300) * 1000)}]'
SH
chmod +x "$S/stub/claude"; export PATH="$S/stub:$PATH"

run() { # one pass over every emitter
  ( cd "$S" && export JIVA_NAME=w1 GIT_AUTHOR_NAME=d GIT_AUTHOR_EMAIL=d@d GIT_COMMITTER_NAME=d GIT_COMMITTER_EMAIL=d@d
    "$V" claim a; echo x >> "$S/a"; "$V" report note "x"; "$V" ship "t$RANDOM"; echo hi | "$V" handoff
    "$V" ask "q?" "y|n" y; JIVA_ASK_TTL=-1 "$V" ask "q2?" "y|n" n; "$V" answer "$(jq -r .id "$J/asks/open.jsonl" | head -1)"
  ) >/dev/null 2>&1
  ( source "$H/core/watchdog.sh"; toast() { :; }; T() { [[ $1 == list-panes ]] && echo "%1 queen 0"; }
    JV=true; CEIL=1000; NUDGE=850; echo w1 > "$J/launch/w1"; touch "$J/rotate/w1"; rm -f "$J/nudged/w1"
    echo '{"tok":900,"q5h":90,"q7d":10}' > "$J/state/w1.json"; rm -f "$J/history.tok"
    tick; echo '{"tok":900,"q5h":10,"q7d":10}' > "$J/state/w1.json"; tick
    flag w1 burn; missing[w1]=1; heal ""; HEAL_MAX=1; heal_ok w1
    mkdir -p "$J/lease"; echo "1 sid %1" > "$LEASE"; lease_tick; lease_take sid %1; lease_tick ) >/dev/null 2>&1
}
run; n1=$(wc -l < "$HJ" 2>/dev/null || echo 0); sum1=$(md5sum < "$HJ")

# kind → required fields (jq types); must match notes/history.md exactly
declare -A SHAPE=(
  [claim]='n:number' [report]='st:string' [ship]='sha:string' [handoff]='lines:number'
  [ask]='id:string class:string' [answer]='id:string by:string' [expire]='id:string class:string'
  [nudge]='name:string tok:number' [life]='name:string why:string' [trip]='name:string trip:string'
  [park]='name:string why:string' [heal]='name:string' [quota]='st:string q5h:number q7d:number'
  [lease]='st:string' [tok]='tok:number s:object')
for k in "${!SHAPE[@]}"; do
  q='(.ts | type == "number")'; for f in ${SHAPE[$k]}; do q+=" and (.${f%%:*} | type == \"${f#*:}\")"; done
  got=$(jq -c --arg k "$k" "select(.kind == \$k) | ($q)" "$HJ" | sort -u | tr '\n' ' ')
  [[ $got == "true " ]] && ok "kind $k: ${SHAPE[$k]}" || no "kind $k shape/absent: '${got}'"
done
ex=$(jq -r .kind "$HJ" | sort -u | grep -vxE "$(IFS='|'; echo "${!SHAPE[*]}")" | tr '\n' ' ')
[[ -z $ex ]] && ok "no undocumented kinds" || no "undocumented kinds: $ex"
grep -q '"why":"rotate"' "$HJ" && grep -q '"why":"heal"' "$HJ" && ok "life: rotate + heal" || no "life why missing"
for k in "${!SHAPE[@]}"; do grep -q "^- \`$k\`" "$H/notes/history.md" || no "notes/history.md lacks $k"; done

run; n2=$(wc -l < "$HJ")
(( n2 > n1 )) && [[ $(head -n "$n1" "$HJ" | md5sum) == "$sum1" ]] && ok "append-only ($n1 → $n2 lines, prefix intact)" ||
  no "not append-only: $n1 → $n2"
(( $(jq -c 'select(.kind == "tok")' "$HJ" | wc -l) == 2 )) && ok "tok: one snapshot per run (2 ticks each)" || no "tok count"

( J="$J"; source "$H/core/history.sh"; hist note x=$'a\n{"kind":"evil"}' "lbl=$(printf 'z%.0s' {1..200})" 'bad key=1'
  for _ in 1 2 3; do hist_tok '{"tok":1}'; done; JIVA_HIST_TOK=0 hist_tok '{"tok":2}' )
n3=$(wc -l < "$HJ")
(( n3 == n2 + 2 )) && ok "newline value → 1 line; 3 tok calls in 300s → 0, TOK=0 → 1" || no "lines $n2 → $n3, want +2"
jq -e . "$HJ" >/dev/null && ! grep -q '^{"kind":"evil"' "$HJ" && ok "every line is JSON, no injection" || no "injection"
l=$(jq -r 'select(.kind == "note") | .lbl | length' "$HJ"); [[ $l == 80 ]] && ok "200-char label → 80" || no "label len $l"
out="$(bash -c "set -e; J=/proc/nope/.jiva; source '$H/core/history.sh'; hist x n=1; hist_tok '{}'; echo alive" 2>&1)"
[[ $out == alive ]] && ok "unwritable J never fails a set -e caller" || no "unwritable: $out"
[[ $("$H/core/jiva.sh" history 2 | wc -l) == 2 ]] && ok "jiva history 2 → 2 lines" || no "jiva history tail"
( cd "$S" && export JIVA_NAME=w2; </dev/null "$V" handoff ) >/dev/null 2>&1; rc=$?
(( rc == 1 )) && [[ ! -e $J/handoff/w2.md && ! -e $J/rotate/w2 ]] && ok "empty handoff → exit 1, no file, no rotate" ||
  no "empty handoff: rc=$rc or file/rotate written"
( cd "$S" && export JIVA_NAME=w2; echo hi | "$V" handoff ) >/dev/null 2>&1 && [[ -s $J/handoff/w2.md ]] &&
  ok "piped handoff still saves" || no "piped handoff failed"
exit $bad
