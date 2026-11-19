#!/usr/bin/env bash
# doctor-perm — perm-relay.sh against a scratch .jiva in /tmp with JIVA_ASK_WAIT=1: (a) no answer →
# exit 0, .timeout.json, flag line `<ts> <session> <tool>` in flags/perm-timeout; (b) answer allow →
# allow decision, no flag; (c) deny → deny; STOP → flag too. Prints ok/FAIL; exit 1 on any FAIL.
set -uo pipefail
H="$(cd "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")/.." && pwd)"
S="$(mktemp -d /tmp/jiva-doctor-XXXXXX)"; trap 'rm -rf "$S"' EXIT
F="$S/.jiva/flags/perm-timeout"; A="$S/.jiva/asks"
bad=0
ok() { printf 'ok    perm %s\n' "$1"; }
no() { printf 'FAIL  perm %s\n' "$1"; bad=1; }
t() { local l=$1; shift; if "$@"; then ok "$l"; else no "$l"; fi; }
req='{"hook_event_name":"PermissionRequest","session_id":"s-doc","tool_name":"Bash","tool_input":{"command":"ls"}}'
relay() { printf '%s' "$req" | env -u JIVA_NAME CLAUDE_PROJECT_DIR="$S" JIVA_ASK_WAIT=1 "$H/core/hooks/perm-relay.sh"; }
answer() { # word — answer the first pending ask once the hook posts it
  for _ in $(seq 20); do
    for f in "$A"/*.json; do
      [[ -e $f && $f != *.done.json && $f != *.timeout.json ]] && { echo "$1" > "${f%.json}.answer"; return; }
    done; sleep 0.1
  done
}

# (a) no answer → native prompt (exit 0, no output), timeout record, flag line
out="$(relay)"; rc=$?
t "timeout exits 0 silently" test "$rc/$out" = "0/"
t "timeout leaves .timeout.json" test -n "$(compgen -G "$A/*.timeout.json")"
t "timeout flag line '<ts> s-doc Bash'" grep -Eqx '[0-9]+ s-doc Bash' "$F"
rm -f "$F" "$A"/*

# (b) allow → decision allow, no flag
answer allow & out="$(relay)"; wait
t "allow → decision allow" test "$(jq -r .hookSpecificOutput.decision.behavior <<<"$out")" = allow
t "allow writes no flag" test ! -e "$F"

# (c) deny → decision deny
answer deny & out="$(relay)"; wait
t "deny → decision deny" test "$(jq -r .hookSpecificOutput.decision.behavior <<<"$out")" = deny

# STOP → flag too; flag keeps last 20 lines; rm clears
touch "$S/.jiva/STOP"; for _ in $(seq 22); do relay >/dev/null; done; rm "$S/.jiva/STOP"
t "STOP flags; capped at 20 lines" test "$(wc -l < "$F")" = 20
rm "$F"; t "rm clears the flag" test ! -e "$F"
exit $bad
