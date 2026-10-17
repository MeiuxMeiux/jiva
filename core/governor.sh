#!/usr/bin/env bash
# governor — fleet pause/resume + fleet $ cap (docs/history/PLAN.md "Loops"). `.jiva/paused` = "<epoch> <reason…>".
# While paused the watchdog keeps writing state but does no dead-pane heal, no lease spawn and no rotation
# respawn; a session at ≥95% of the context ceiling gets ONE "handoff now" say per life (nudged/<n>.pause).
# Fleet $ cap: JIVA_FLEET_USD (0 = off) vs Σ sessions[].usd → auto-pause once + flags/fleet-usd + toast +
# hist; `resume` clears both. governor/capped keeps it from re-pausing until Σ drops below the cap.
#   governor.sh pause [reason] | resume | status       (sourced by watchdog/status: paused, gov_tick)
set -uo pipefail
# shellcheck source=core/lib.sh
declare -F T >/dev/null || source "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")/lib.sh"
declare -F hist >/dev/null || source "$JIVA_HOME/core/history.sh"
GOV="$J/paused"

paused() { [[ -e $GOV ]]; }
gov_reason() { local ts r; read -r ts r < "$GOV" 2>/dev/null || return 1; [[ $ts =~ ^[0-9]+$ ]] || ts=0; echo "${r:-paused} ($(( $(date +%s) - ${ts:-0} ))s ago)"; }
gov_pause() { # reason → .jiva/paused + hist; 1 if already paused
  paused && return 1; mkdir -p "$J"; echo "$(date +%s) ${1:-paused by hand}" > "$GOV"
  hist governor st=pause why="${1:-hand}"
}
gov_resume() { # → rm paused + flags/fleet-usd + hist; 1 if not paused
  paused || return 1; rm -f "$GOV" "$J/flags/fleet-usd"; hist governor st=resume
}
gov_tick() { # merged-json → fleet $ cap check; watchdog calls it each tick (needs toast)
  local cap=${JIVA_FLEET_USD:-0} sum; sum="$(jq -r '[.sessions[].usd // 0] | add // 0' <<<"$1")"
  awk -v c="$cap" 'BEGIN { exit !(c > 0) }' || { rm -f "$J/governor.capped"; return 0; }
  if awk -v s="$sum" -v c="$cap" 'BEGIN { exit !(s >= c) }'; then
    [[ -e $J/governor.capped ]] && return 0
    touch "$J/governor.capped"; printf 'fleet $%.2f ≥ cap $%s\n' "$sum" "$cap" > "$J/flags/fleet-usd"
    gov_pause "fleet \$$(printf %.2f "$sum") ≥ cap \$$cap"
    toast "jiva: fleet \$$(printf %.2f "$sum") ≥ JIVA_FLEET_USD \$$cap — paused (jiva pause/resume)"
  else rm -f "$J/governor.capped"; fi
}
gov_handoff() { # name tok → while paused, one "handoff now" say per life at ≥95% of CEIL
  paused && (( $2 * 100 >= CEIL * 95 )) && once "$1" pause || return 0
  "$JV" say "$1" "JIVA governor: fleet paused and context at ${2} tokens — handoff now: \`jiva handoff\`, then stop."
}

[[ ${BASH_SOURCE[0]} == "$0" ]] || return 0
case "${1:-status}" in
  pause) shift; gov_pause "$*" && echo "jiva: paused — no heal, no lease spawn, no rotation (jiva resume)" ||
           echo "jiva: already paused: $(gov_reason)" ;;
  resume) gov_resume && echo "jiva: resumed" || echo "jiva: not paused" ;;
  status) if paused; then echo "paused: $(gov_reason)"; else echo "running"; fi ;;
  *) echo "usage: governor.sh pause [reason] | resume | status" >&2; exit 2 ;;
esac
