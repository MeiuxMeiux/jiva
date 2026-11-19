#!/usr/bin/env bash
# doctor-asks — asks lifecycle against a scratch .jiva in /tmp, with `say` stubbed to a log ($JIVA_SAY):
# ask → inbox → answer (text / default) → say text; a decision ask expires to its default, a deploy ask
# never does; one digest per 0→≥1; statusline `asks N` from a fake file; check.sh skips a deleted
# tracked file. Prints ok/FAIL; exit 1 on any FAIL.
set -uo pipefail
H="$(cd "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")/.." && pwd)"
S="$(mktemp -d /tmp/jiva-doctor-XXXXXX)"; trap 'rm -rf "$S"' EXIT
printf '#!/usr/bin/env bash\necho "$1|$2" >> %q\n' "$S/says" > "$S/say"; chmod +x "$S/say"; : > "$S/says"
export JIVA_TARGET="$S" JIVA_SAY="$S/say" JIVA_DESK=desk
V() { JIVA_NAME=queen "$H/core/verbs.sh" "$@"; }
# shellcheck source=core/lib.sh
source "$H/core/lib.sh"
# shellcheck source=core/asks.sh
source "$H/core/asks.sh"
bad=0
ok() { printf 'ok    asks %s\n' "$1"; }
no() { printf 'FAIL  asks %s\n' "$1"; bad=1; }
t() { local l=$1; shift; if "$@"; then ok "$l"; else no "$l"; fi; }
idof() { grep -o 'ask [0-9a-f]\{6\}' <<<"$1" | cut -c5-; }
closed() { jq -r --arg i "$1" "select(.id == \$i) | .$2" "$A/answered.jsonl" 2>/dev/null; }

# ask → inbox → answer with text
id="$(idof "$(V ask "ship w2?" "yes|no" no)")"
t "ask writes one decision line" test "$(jq -r '"\(.class) \(.opts | length) \(.deadline - .ts)"' "$A/open.jsonl")" = "decision 2 1800"
t "inbox shows id, from, default" grep -q "^$id .*queen \[decision\]: ship w2?.*default: no" <(V inbox 1)
V answer "$id" yes >/dev/null
t "answer closes it" test "$(ask_count)" = 0
t "answer recorded" test "$(closed "$id" answer)" = yes
t "asker gets the say text" grep -qx "queen|JIVA answer $id: yes" "$S/says"

# answer with no text applies the default
id="$(idof "$(V ask "rebase?" "a,b" b)")"; V answer "$id" >/dev/null
t "bare answer applies default" test "$(closed "$id" answer)" = b
t "unknown id refused" bash -c "! JIVA_NAME=queen '$H/core/verbs.sh' answer zzzzzz 2>/dev/null"
t "bad class refused" bash -c "! JIVA_NAME=queen '$H/core/verbs.sh' ask q o d bogus 2>/dev/null"
V claim a b/c d >/dev/null; V unclaim b/c/ d >/dev/null
t "unclaim drops only those paths" test "$(cat "$J/claims/queen")" = a
t "unclaim with no claims file refused" bash -c "! JIVA_NAME=nob '$H/core/verbs.sh' unclaim a 2>/dev/null"

# expiry: decision → default once; deploy stays open
id="$(idof "$(JIVA_ASK_TTL=-1 V ask "pick a name?" "x|y" y)")"
dep="$(idof "$(JIVA_ASK_TTL=-1 V ask "deploy site?" "go|hold" go deploy)")"
ask_expire; ask_expire
t "expired decision got its default" test "$(closed "$id" answer)/$(closed "$id" by)" = "y/expired"
t "expired logs expired→default" grep -q "ask $id expired→default: y" "$J/comb.log"
t "expiry applied once" test "$(grep -c "\"id\":\"$id\"" "$A/answered.jsonl")" = 1
t "deploy ask never auto-resolves" test "$(jq -r .id "$A/open.jsonl")/$(closed "$dep" answer)" = "$dep/"

# digest: one say on 0 → ≥1, none inside JIVA_DIGEST, re-surfaced after it
: > "$S/says"; rm -f "$A/digest"; V ask "second?" "" "" >/dev/null
ask_digest; ask_digest
t "one digest for 2 open asks" test "$(grep -c '^desk|JIVA: 2 open asks' "$S/says")" = 1
JIVA_DIGEST=0 ask_digest
t "digest re-surfaces after interval" test "$(grep -c '^desk|' "$S/says")" = 2
: > "$A/open.jsonl"; ask_digest
t "digest resets at 0" test ! -e "$A/digest"

# statusline: count straight from the file
printf '{}\n{}\n{}\n' > "$A/open.jsonl"
out="$(echo '{"context_window":{"total_input_tokens":12000}}' | CLAUDE_PROJECT_DIR="$S" JIVA_NAME=w1 \
  "$H/core/hooks/statusline.sh")"
t "statusline prints asks 3 ($out)" grep -q ' · asks 3$' <<<"$out"
sl() { echo '{"context_window":{"total_input_tokens":170000,"used_percentage":88}}' | CLAUDE_PROJECT_DIR="$S" \
  JIVA_ROLE=$1 JIVA_NAME=$1 "$H/core/hooks/statusline.sh"; }
t "desk at 170k with asks open: no rotate nudge" bash -c '! grep -q ROTATE <<<"$1"' _ "$(sl desk)"
: > "$A/open.jsonl"
t "desk at 170k, asks 0: rotate nudge" grep -q ' · ROTATE: ctx ≥150k, no asks' <<<"$(sl desk)"
t "worker at 170k: no desk nudge (watchdog's job)" bash -c '! grep -q ROTATE <<<"$1"' _ "$(sl w1)"

# desk recap: session-start role=desk → 3 recap lines (last ship, open asks, flags)
printf '{}\n{}\n' > "$A/open.jsonl"; mkdir -p "$J/flags"; touch "$J/flags/w3"
echo "{\"ts\":$(date +%s),\"kind\":\"ship\",\"who\":\"w2\",\"sha\":\"abc1234\"}" >> "$J/history.jsonl"
rc="$(CLAUDE_PROJECT_DIR="$S" JIVA_ROLE=desk JIVA_NAME=desk "$H/core/hooks/session-start.sh" </dev/null |
  jq -r .hookSpecificOutput.additionalContext | grep '^recap: ')"
t "recap: 3 lines" test "$(grep -c '' <<<"$rc")" = 3
t "recap: last ship abc1234 by w2" grep -q '^recap: last ship abc1234 by w2 0m ago$' <<<"$rc"
t "recap: open asks 2" grep -q '^recap: open asks 2 ' <<<"$rc"
t "recap: flags w3" grep -q '^recap: flags w3 $' <<<"$rc"
t "recap: worker gets none" bash -c "! CLAUDE_PROJECT_DIR='$S' JIVA_ROLE=worker JIVA_NAME=w1 '$H/core/hooks/session-start.sh' </dev/null | grep -q recap:"
: > "$A/open.jsonl"; rm -f "$J/flags/w3"

# message ttl: comb lines carry an epoch stamp; inbox/watch hide lines past JIVA_MSG_TTL (asks keep deadlines)
printf '01:00 w5     note: stale line\t%s\n' $(( $(date +%s) - 30000 )) >> "$J/comb.log"
V report note "fresh line" >/dev/null
t "ttl: comb line stamped" grep -qP '^\d\d:\d\d queen  note: fresh line\t\d{10}$' "$J/comb.log"
out="$(V inbox 50)"
t "ttl: inbox hides stale line" bash -c '! grep -q "stale line" <<<"$1"' _ "$out"
t "ttl: inbox shows fresh line, stamp stripped" grep -qP '^\d\d:\d\d queen  note: fresh line$' <<<"$out"
t "ttl: JIVA_MSG_TTL widens it" grep -q "stale line" <<<"$(JIVA_MSG_TTL=40000 V inbox 50)"
out="$("$H/core/watch.sh" 2>/dev/null)"
t "ttl: watch hides stale, shows fresh" bash -c 'grep -q "fresh line" <<<"$1" && ! grep -q "stale line" <<<"$1"' _ "$out"

# check.sh: a tracked file deleted in the working tree is skipped, not a crash
R="$S/repo"; mkdir -p "$R/core"; printf '#!/usr/bin/env bash\necho hi\n' > "$R/core/x.sh"
git -C "$R" init -q && git -C "$R" add . && git -C "$R" -c user.name=d -c user.email=d@d commit -qm x
rm "$R/core/x.sh"
t "check.sh skips deleted tracked file" bash -c "cd '$R' && '$H/core/check.sh' >/dev/null 2>&1"
exit $bad
