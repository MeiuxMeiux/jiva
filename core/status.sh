#!/usr/bin/env bash
# status — one-line fleet summary + a row per session, from $J/state.json (written by the watchdog).
# Never crashes on a bad runtime: tmux down → "runtime down"; state.json unreadable → says so (the
# watchdog rewrites it every tick, checked before tmux so bad JSON never reads as "runtime down");
# ts older than JIVA_WD_STALE (30s) → "watchdog dead", lease unknown. Line 1 is prefixed "PAUSED · "
# (.jiva/paused, core/governor.sh) and/or "STOPPED · " (lib.sh stopped).
#   status.sh bar   tmux status-right body (set by the watchdog): $J/bar, or a red "watchdog dead" chip.
#   status.sh dash  "dash http://127.0.0.1:<port>/" when $J/dash/pid is alive, else "dash: down (jiva dash start)".
set -uo pipefail
# shellcheck source=core/lib.sh
source "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")/lib.sh"
STALE="${JIVA_WD_STALE:-30}"
age() { local ts; ts="$(jq -er '.ts | numbers' "$J/state.json" 2>/dev/null)" || return 1; echo $(( $(date +%s) - ts )); }
dash() { local p; p="$(cat "$J/dash/pid" 2>/dev/null)"
  if [[ $p =~ ^[0-9]+$ ]] && kill -0 "$p" 2>/dev/null && [[ -s $J/dash/port ]]; then
    echo "dash http://127.0.0.1:$(cat "$J/dash/port")/"; else echo "dash: down (jiva dash start)"; fi; }

[[ ${1:-} == dash ]] && { dash; exit 0; }
if [[ ${1:-} == bar ]]; then
  if ! a="$(age)" || (( a > STALE )); then
    printf '#[fg=white,bg=red,bold] watchdog dead (state %s) — just restart-watchdog #[default]\n' "${a:+${a}s old}${a:-unreadable}"
  else cat "$J/bar" 2>/dev/null; fi
  exit 0
fi
pre=""; [[ -e $J/paused ]] && pre="PAUSED · "; declare -F stopped >/dev/null && stopped && pre="STOPPED · $pre"
unreadable() { echo "${pre}jiva: state.json unreadable — the watchdog rewrites it next tick"; exit 1; }
[[ -e $J/state.json ]] && { age >/dev/null || unreadable; }   # bad/empty JSON says so first, whatever tmux is doing
T ls >/dev/null 2>&1 || { echo "${pre}jiva: runtime down (tmux -L $SOCK) — \`jiva up\`; lease not held · $(dash)"; exit 1; }
[[ -s $J/state.json ]] || { echo "${pre}jiva: no state.json in $J (watchdog not started? \`just restart-watchdog\`)" >&2; exit 1; }
a="$(age)" || unreadable
lease='lease \(.lease // "none")'; rc=0
if (( a > STALE )); then echo "${pre}jiva: watchdog dead (state ${a}s old) — \`just restart-watchdog\`"; lease='lease unknown'; rc=1; pre=""; fi
jq -r --arg pre "$pre" "\"\(\$pre)\(.live) live\(if (.trust // 0) > 0 then \" · \(.trust) at trust dialog\" else \"\" end) · \(.flags) flag · \(.tok/1000|floor)k · $lease · $(dash)\",
  (.sessions[] | \"  \(if .soul.slot != null then \"\(.soul.name) · \(.name)\" else .name end)\t\(.status)\t\(.tok/1000|floor)k\")" "$J/state.json" 2>/dev/null || unreadable
exit $rc
