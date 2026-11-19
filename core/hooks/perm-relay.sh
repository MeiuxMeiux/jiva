#!/usr/bin/env bash
# PermissionRequest hook (opt-in; not wired in core/settings.json) — relays the prompt to the desk,
# never decides on its own. Posts .jiva/asks/<id>.json; the keeper answers by writing allow|deny
# to .jiva/asks/<id>.answer (in the JIVA repo: `just j-perm-answer <id> allow|deny`).
# No answer within JIVA_ASK_WAIT secs, or .jiva/STOP present → exit 0 silently → native prompt in the pane,
# and append `<ts> <session> <tool>` to .jiva/flags/perm-timeout (last 20 lines; desk clears with rm).
set -euo pipefail
# shellcheck source=core/lib.sh
JIVA_TARGET="${CLAUDE_PROJECT_DIR:-${JIVA_TARGET:-}}"; source "$(dirname "$(readlink -f "$0")")/../lib.sh"
root="$TARGET"; dir="$J/asks"; mkdir -p "$dir"
flag() { # tool — visible timeout: state.json `flags` counts it, dash shows it
  local f="$J/flags/perm-timeout"; mkdir -p "$J/flags"
  echo "$(date +%s) ${JIVA_NAME:-$(jq -r '.session_id // "?"' <<<"$req" 2>/dev/null)} $1" >> "$f"
  tail -n 20 "$f" > "$dir/.pt.tmp" && mv "$dir/.pt.tmp" "$f"
}
req="$(cat)"; tool="$(jq -r '.tool_name // "?"' <<<"$req" 2>/dev/null || echo '?')"
[[ -e "$root/.jiva/STOP" ]] && { flag "$tool"; exit 0; }
id="$(date +%s%N)-$$"
printf '%s\n' "$req" > "$dir/$id.json"
for ((i = 0; i < ${JIVA_ASK_WAIT:-20} * 2; i++)); do
  if [[ -s "$dir/$id.answer" ]]; then
    ans="$(tr -d '[:space:]' < "$dir/$id.answer")"
    mv "$dir/$id.json" "$dir/$id.done.json"; rm -f "$dir/$id.answer"
    if [[ $ans == allow ]]; then b='{"behavior":"allow"}'
    else b='{"behavior":"deny","message":"denied at the desk"}'; fi
    printf '{"hookSpecificOutput":{"hookEventName":"PermissionRequest","decision":%s}}\n' "$b"
    exit 0
  fi
  sleep 0.5
done
mv "$dir/$id.json" "$dir/$id.timeout.json"; flag "$tool"; exit 0
