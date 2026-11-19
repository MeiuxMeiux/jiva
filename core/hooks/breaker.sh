#!/usr/bin/env bash
# breaker — PostToolUse hook. Ring of the last 8 call hashes per session; 4 identical in a row
# flags `repeat` and exits 2 so the model sees the stderr line.
in="$(cat)"
# shellcheck source=core/lib.sh
JIVA_TARGET="${CLAUDE_PROJECT_DIR:-${JIVA_TARGET:-}}"; source "$(dirname "$(readlink -f "$0")")/../lib.sh"
stopped && exit 0   # .jiva/STOP: no ring or flag writes
mkdir -p "$J"/{state,flags}
name="${JIVA_NAME:-$(jq -r '.session_id // "anon"' <<<"$in")}"; name="${name//[^A-Za-z0-9_.-]/_}"   # a path component
ring="$J/state/$name.calls"
h="$(jq -c '[.tool_name, .tool_input]' <<<"$in" | sha1sum | cut -c1-40)"
if [[ $(tail -n 1 "$ring" 2>/dev/null) != "$h" && $(cat "$J/flags/$name" 2>/dev/null) == repeat ]]; then
  rm -f "$J/flags/$name"   # a non-identical call clears a repeat flag
fi
{ tail -n 7 "$ring" 2>/dev/null; echo "$h"; } > "$ring.tmp" && mv "$ring.tmp" "$ring"
if (( $(tail -n 4 "$ring" | grep -cx "$h") == 4 )); then
  echo repeat > "$J/flags/$name"
  echo "JIVA breaker: identical tool call ×4 — change approach or report blocked" >&2
  exit 2
fi
exit 0
