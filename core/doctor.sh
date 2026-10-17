#!/usr/bin/env bash
# jiva doctor — budgets as tests (docs/history/PLAN.md). One line per check: ok/FAIL. Exit 1 on any FAIL.
#   doctor.sh         static checks: boot payload, handoff/card sizes, state freshness, hook targets
#   doctor.sh live    also kill -9 a scratch worker (w9) and require the watchdog to respawn it ≤45s
#   doctor.sh breakers  only the breaker unit tests (core/doctor-breakers.sh; static runs them too)
#   doctor.sh asks      only the asks lifecycle tests (core/doctor-asks.sh; static runs them too)
#   doctor.sh perm      only perm-relay timeout/allow/deny + flag (core/doctor-perm.sh, scratch; static too)
#   doctor.sh lease     only the boss-lease tests (core/doctor-lease.sh, scratch TARGET + socket; static too)
#   doctor.sh dash      only the dashboard endpoints /flags /asks /lease (core/doctor-dash.sh, scratch port; static too)
#   doctor.sh fault     only the fault-injection tests (core/doctor-fault.sh, scratch TARGET + socket, stub claude; static too)
#   doctor.sh notify    only the notify tests (core/doctor-notify.sh, scratch; static too)
#   doctor.sh history   only the history writer tests (core/doctor-history.sh, scratch J; static too)
#   doctor.sh souls     only the soul-binding tests (core/doctor-souls.sh, scratch J + stub pack; static too)
#   doctor.sh watch     only the live-view tests (core/doctor-watch.sh; static too)
#   doctor.sh budgets   only CLAUDE.md/caps/150k (75%) nudge/state diet/version+spike/Stop-hook (core/doctor-budgets.sh; static too)
#   doctor.sh fleet     only gate rows/card lint/desk digest/profile/lean launch (core/doctor-fleet.sh, scratch; static too)
#   doctor.sh payload   only the boot-payload checks (doctor-lease runs it from a fake worker pane)
#   doctor.sh plugin    only plugin-vs-settings hooks mode (core/doctor-plugin.sh, scratch config; static too)
set -uo pipefail
# shellcheck source=core/lib.sh
source "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")/lib.sh"
bad=0
ok() { printf 'ok    %s\n' "$1"; }
no() { printf 'FAIL  %s\n' "$1"; bad=1; }

# boot payload per role: additionalContext chars/4 ≈ tokens, budget 1500
payload() { # role name
  local n
  n="$(JIVA_DOCTOR=1 CLAUDE_PROJECT_DIR="$TARGET" JIVA_ROLE=$1 JIVA_NAME=$2 "$JIVA_HOME/core/hooks/session-start.sh" </dev/null |
    jq -r '.hookSpecificOutput.additionalContext | length / 4 | floor')" || { no "boot payload $2: hook failed"; return; }
  (( n <= 1500 )) && ok "boot payload $2: ~${n} tok (≤1500)" || no "boot payload $2: ~${n} tok (>1500)"
}

sizes() { # glob max label
  local f n over=""
  for f in $1; do
    [[ -e $f ]] || continue
    n=$(wc -l < "$f"); (( n <= $2 )) || over+=" ${f#"$J"/}($n)"
  done
  [[ -z $over ]] && ok "$3 ≤$2 lines" || no "$3 over $2 lines:$over"
}

state() {
  if ! T ls >/dev/null 2>&1; then ok "state.json: runtime down (skipped)"; return; fi
  local ts age
  ts="$(jq -r '.ts // 0' "$J/state.json" 2>/dev/null || echo 0)"
  age=$(( $(date +%s) - ts ))
  (( age <= 30 )) && ok "state.json fresh (${age}s)" || no "state.json stale (${age}s > 30s) — watchdog down?"
}

hooks() { # every command in settings.json → first word resolves to an executable file
  local cmd path missing=""
  while IFS= read -r cmd; do
    path="${cmd%% *}"; path="${path//\"/}"; path="${path//\$CLAUDE_PROJECT_DIR/$JIVA_HOME}"
    [[ -f $path && -x $path ]] || missing+=" $path"
  done < <(jq -r '.. | objects | select(.type? == "command") | .command' "$JIVA_HOME/core/settings.json")
  [[ -z $missing ]] && ok "settings.json hooks point at executables" || no "settings.json hooks missing/non-exec:$missing"
}

pid_of() { claude agents --json 2>/dev/null | jq -r --arg n "$1" --arg r "$TARGET" \
  '[.[] | select(.name == $n and .cwd == $r) | .pid] | first // empty'; }

live() { # scratch worker w9: spawn, kill -9, expect the watchdog to bring it back
  local w=w9 old new=""
  if ! T has-session -t jiva 2>/dev/null; then no "live: jiva server down (just up first)"; return; fi
  "$JIVA_HOME/core/jiva.sh" spawn worker "$w" >/dev/null || { no "live: spawn $w failed"; cleanup "$w"; return; }
  for _ in $(seq 15); do old="$(pid_of "$w")"; [[ -n $old ]] && break; sleep 1; done
  [[ -n $old ]] || { no "live: $w never showed in claude agents"; cleanup "$w"; return; }
  kill -9 "$old"
  for _ in $(seq 45); do
    sleep 1; new="$(pid_of "$w")"
    [[ -n $new && $new != "$old" ]] && break; new=""
  done
  [[ -n $new ]] && ok "live: kill -9 $w self-healed (pid $old → $new)" ||
    no "live: kill -9 $w not respawned in 45s — watchdog lacks dead-pane respawn?"
  cleanup "$w"
}

cleanup() { T kill-window -t "jiva:$1" 2>/dev/null; rm -f "$J/launch/$1" "$J/state/$1.json" "$J/claims/$1"; }

[[ ${1:-} == payload ]] && { payload boss boss; payload worker w1; exit $bad; }   # doctor-lease regression
[[ ${1:-} == breakers ]] && exec "$JIVA_HOME/core/doctor-breakers.sh"
[[ ${1:-} == asks ]] && exec "$JIVA_HOME/core/doctor-asks.sh"
[[ ${1:-} == perm ]] && exec "$JIVA_HOME/core/doctor-perm.sh"
[[ ${1:-} == lease ]] && exec "$JIVA_HOME/core/doctor-lease.sh"
[[ ${1:-} == dash ]] && exec "$JIVA_HOME/core/doctor-dash.sh"
[[ ${1:-} == plugin ]] && exec "$JIVA_HOME/core/doctor-plugin.sh"
[[ ${1:-} == fault ]] && exec "$JIVA_HOME/core/doctor-fault.sh"
[[ ${1:-} == souls ]] && exec "$JIVA_HOME/core/doctor-souls.sh"
[[ ${1:-} == watch ]] && exec "$JIVA_HOME/core/doctor-watch.sh"
[[ ${1:-} == notify ]] && exec "$JIVA_HOME/core/doctor-notify.sh"
[[ ${1:-} == history ]] && exec "$JIVA_HOME/core/doctor-history.sh"
[[ ${1:-} == fleet ]] && exec "$JIVA_HOME/core/doctor-fleet.sh"
[[ ${1:-} == budgets ]] && exec "$JIVA_HOME/core/doctor-budgets.sh"
payload boss boss
payload worker w1
sizes "$J/handoff/*.md" 40 "handoffs"
sizes "$J/tasks/*.md" 20 "task cards"
state
hooks
"$JIVA_HOME/core/doctor-breakers.sh" || bad=1
"$JIVA_HOME/core/doctor-asks.sh" || bad=1
"$JIVA_HOME/core/doctor-plugin.sh" || bad=1
"$JIVA_HOME/core/doctor-perm.sh" || bad=1
"$JIVA_HOME/core/doctor-lease.sh" || bad=1
"$JIVA_HOME/core/doctor-dash.sh" || bad=1
"$JIVA_HOME/core/doctor-fault.sh" || bad=1
"$JIVA_HOME/core/doctor-watch.sh" || bad=1
"$JIVA_HOME/core/doctor-souls.sh" || bad=1
"$JIVA_HOME/core/doctor-notify.sh" || bad=1
"$JIVA_HOME/core/doctor-history.sh" || bad=1
"$JIVA_HOME/core/doctor-budgets.sh" || bad=1
"$JIVA_HOME/core/doctor-fleet.sh" || bad=1
[[ ${1:-} == live ]] && live
exit $bad
