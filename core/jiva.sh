#!/usr/bin/env bash
# jiva — launcher + verbs for any repo. Sessions live on a private tmux server (one socket per repo),
# never your own. Run from the target repo (or set JIVA_TARGET); code always comes from JIVA_HOME.
#   plugin [install|uninstall|status|mode]  local plugin at user scope (plugin/install.sh); mode = hooks source
#   init                make this repo hive-ready (.jiva/, .gitignore, CLAUDE.md pointer if absent)
#   up [profile]        watchdog + cells: solo | duo[:N] | full[:N] | N (auto from host + quota; prints why)
#   spawn <role> <name> start one session in its own window
#   respawn <name>      kill the pane and boot a fresh body (same role/name, re-reads boot payload)
#   assign <w> <card>   install a task card for worker <w>, respawn it, kick it off
#   restart-watchdog    respawn the watchdog pane (picks up core/watchdog.sh edits; hive untouched)
#   say <name> <text>   type "[HH:MM] text" into a session (the ts is the message ttl stamp)
#   down                stop everything (kills this target's tmux server + dash only)
#   status              one-line hive summary from .jiva/state.json
#   doctor [live|breakers|asks|perm|lease|plugin|watch|fault]  budgets as tests; `live` kill -9 self-heal; others run only that set
#   dash [start|stop|url]  tier-1 dashboard on 127.0.0.1:<random port>
#   watch               one live terminal view: bar + open asks + last comb lines (core/watch.sh)
#   mine [n]            rank repeated Bash commands from this repo's transcripts (recipe candidates)
#   roster [gen|check|show] [pack]  name/color/avatar pack tooling (scripts/roster.sh; default pack)
#   pick <paths…>       best idle worker for these paths (affinity table; queen still chooses)
#   check               files ≤150 lines, notes ≤30, scripts parse, shellcheck (run in the target)
#   scratch <name> [rm] make (print) or clean /tmp/jiva-scratch/<name> — never rm a computed path yourself
#   pause [reason]      hive pause: watchdog stops heal, lease spawn and rotation (core/governor.sh)
#   resume              lift the pause (and the hive $ cap flag)
#   governor [status]   running, or paused: <reason> (<age>)
#   spike               re-test version-sensitive assumptions on scratch socket jiva-spike
#   claim|unclaim|report|ask|answer|ship|handoff|inbox|pending  session verbs (core/verbs.sh)
#   help                this list. Workers: soft cap 6 (JIVA_CONFIRM=1 above it), hard cap 12.
set -euo pipefail
# shellcheck source=core/lib.sh
source "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")/lib.sh"
BOSS_MODEL="${JIVA_BOSS_MODEL:-opus}"; WORKER_MODEL="${JIVA_WORKER_MODEL:-opus}"   # aliases; pin ids in ~/.config/jiva/env
DESK="${JIVA_DESK:-desk}"
# a tmux server started from inside claude (desk/queen `jiva up`) leaks that session's identity to every pane
LEAKED="CLAUDECODE CLAUDE_PID CLAUDE_EFFORT CLAUDE_PROJECT_DIR CLAUDE_CODE_SESSION_ID CLAUDE_CODE_CHILD_SESSION
  CLAUDE_CODE_ENTRYPOINT CLAUDE_CODE_EXECPATH CLAUDE_CODE_MESSAGING_SOCKET CLAUDE_CODE_MESSAGING_TOKEN CLAUDE_CODE_SESSION_ATTENDED"

wdcmd() { echo "JIVA_TARGET=$(printf %q "$TARGET") $(printf %q "$JIVA_HOME/core/watchdog.sh"); exec bash"; }
server() {
  mkdir -p "$J"/{launch,tasks,handoff,state,claims}
  T has-session -t jiva 2>/dev/null && return
  T new-session -d -s jiva -n watchdog -x 220 -y 50 -c "$TARGET" "$(wdcmd)"
  T set -g focus-events on
  T set -g status-interval 5
  T set -g status-right '#(cat '"$J"'/bar 2>/dev/null)'
  T set -g status-right-length 80
}

# roster caps (docs/history/PLAN.md): each worker ≈ 1× quota burn, so >6 needs JIVA_CONFIRM=1 and >12 is refused
cap_ok() { # total workers wanted
  (( $1 <= 12 )) || { echo "jiva: $1 workers over hard cap 12 — refused" >&2; return 1; }
  (( $1 <= 6 || ${JIVA_CONFIRM:-0} == 1 )) && return 0
  echo "jiva: $1 workers over soft cap 6 (~$1× quota burn); rerun with JIVA_CONFIRM=1" >&2; return 1
}
workers() { local w n=0; for w in $(T list-windows -t jiva -F '#W' 2>/dev/null); do   # count worker windows
  [[ $(cat "$J/launch/$w" 2>/dev/null) == worker ]] && n=$((n + 1)); done; echo "$n"; }

# governor: refuse new bodies when the weekly or 5h quota is nearly gone
quota_ok() {
  local hi
  hi="$( { cat "$J"/state/*.json 2>/dev/null || true; } | jq -s '[.[] | .q7d, .q5h | numbers] | max // 0')"
  (( ${hi%.*} < ${JIVA_QUOTA_MAX:-85} )) || { echo "jiva: quota at ${hi}% — not spawning" >&2; return 1; }
}

lean() { # lean cell (default; JIVA_LEAN=0 opts out): no MCP servers, no tools a cell never needs (~half the boot context)
  [[ ${JIVA_LEAN:-1} == 0 ]] || printf -- '--strict-mcp-config --disallowedTools %q ' "${JIVA_LEAN_DENY:-Artifact,ArtifactComments,ArtifactData,NotebookEdit}"; }
cmdline() { # role name → shell command for the pane (settings rendered with absolute JIVA_HOME hooks)
  local model=$WORKER_MODEL; [[ $1 == queen ]] && model=$BOSS_MODEL
  render_settings
  printf 'unset %s; PATH=%q:$PATH JIVA_HOME=%q JIVA_TARGET=%q JIVA_ROLE=%q JIVA_NAME=%q JIVA_DESK=%q claude %s--model %q --name %q --settings %q; exec bash' \
    "${LEAKED//[[:space:]]/ }" "$JIVA_HOME/bin" "$JIVA_HOME" "$TARGET" "$1" "$2" "$DESK" "$(lean)" "$model" "$2" "$J/settings.json"
}

ready() { # name → wait for the input prompt; a trust dialog means the keeper must accept once
  local s
  for _ in $(seq 60); do
    s="$(T capture-pane -p -t "jiva:$1" 2>/dev/null)"
    if grep -q 'trust this folder' <<<"$s"; then   # keeper's click: show where, never send the keys
      T select-window -t "jiva:$1"
      echo "tmux -L $SOCK attach -t jiva:$1" >&2
      echo "↓ then Enter to trust (once per repo path); Ctrl-b n for the next one, Ctrl-b d to detach." >&2
      echo "The session boots itself after the click — no re-run needed; \`jiva status\` to confirm." >&2; return 1
    fi
    grep -q 'for agents' <<<"$s" && return 0
    sleep 1
  done
  echo "jiva: $1 not ready" >&2; return 1
}

say() { T send-keys -t "jiva:$1" -l "[$(date +%H:%M)] $2"; sleep 0.3; T send-keys -t "jiva:$1" Enter; }   # ts: ttl

spawn() {
  server; quota_ok
  if T list-windows -t jiva -F '#W' | grep -qx "$2"; then printf '%s\n' "$1" > "$J/launch/$2"; respawn "$2"; return; fi
  [[ $1 != worker ]] || cap_ok $(( $(workers) + 1 ))
  printf '%s\n' "$1" > "$J/launch/$2"
  T new-window -d -t jiva -n "$2" -c "$TARGET" "$(cmdline "$1" "$2")"
  ready "$2"
}

respawn() {
  local role; role="$(cat "$J/launch/$1")"; quota_ok
  rm -f "$J/state/$1.json" "$J/flags/$1"   # a fresh body starts unflagged; parked/ stays for the desk
  T respawn-pane -k -t "jiva:$1" -c "$TARGET" "$(cmdline "$role" "$1")"
  ready "$1"
}

assign() {
  [[ -s $2 ]] || { echo "jiva: no card at $2" >&2; exit 1; }
  (( $(wc -l < "$2") <= 20 )) || { echo "jiva: card over 20 lines" >&2; exit 1; }
  local p; p="$(grep -m1 -o 'Claim:.*' "$2" | sed 's/^Claim:[[:space:]]*//; s/\.[[:space:]].*//; s/\.$//' || true)"   # log the pick, never auto-pick
  # shellcheck disable=SC2086
  [[ -z $p ]] || board_log "${JIVA_NAME:-$DESK}" "assign $1 (pick: $("$JIVA_HOME/core/pick.sh" $p 2>/dev/null || echo none))"
  cp "$2" "$J/tasks/$1.md"; rm -f "$J/handoff/$1.md" "$J/claims/$1" "$J/flags/$1"
  if T list-windows -t jiva -F '#W' 2>/dev/null | grep -qx "$1"; then respawn "$1"; else spawn worker "$1"; fi
  say "$1" "Start your task card."
}

up() { # [profile|N] — core/profile.sh sizes the hive (solo|duo|full, auto from host + quota) and says why
  local plan b l n prof rc=0; preflight >&2 || return 1; plan="$("$JIVA_HOME/core/profile.sh" "${1:-}")" || return 1
  read -r b l n prof <<<"$plan"; sed 1d <<<"$plan"; cap_ok "$n"
  echo "hooks: $(hooks_mode) · models: queen $BOSS_MODEL, worker $WORKER_MODEL"   # plugin installed → settings carry statusLine only (no double-fire)
  T has-session -t jiva 2>/dev/null || rm -f "$J"/launch/* "$J"/claims/*   # fresh up: heal respawns any launch file, so the last hive's cells stay down
  server; echo "$prof" > "$J/profile"   # window 0 is the watchdog; solo → lease never spawns a queen
  if (( b )); then spawn queen queen || rc=1; fi
  if (( l )); then spawn loop loop || rc=1; fi
  for i in $(seq "$n"); do spawn worker "w$i" || rc=1; done
  T list-windows -t jiva -F '#I #W'
  return $rc
}

help() { sed -n '2,/^set -euo/p' "${BASH_SOURCE[0]}" | sed '$d' | sed 's/^# \{0,1\}//'; }

case "${1:-}" in
  init) preflight >&2 || { echo "jiva: install the required tools above, then rerun" >&2; exit 1; }; init_target ;;
  plugin) [[ ${2:-} == mode ]] && { echo "hooks: $(hooks_mode)"; exit; }; shift; exec "$JIVA_HOME/plugin/install.sh" "$@" ;;
  up) up "${2:-}" ;;
  spawn|respawn|assign|say) n="${2:-}"; [[ $1 != spawn ]] || { n="${3:-}"; [[ $2 =~ ^[a-z]+$ ]] || n=; }   # path + tmux-safe
    [[ $n =~ ^[A-Za-z0-9_-]{1,32}$ ]] || { echo "jiva: $1: bad role/name '$n' ([A-Za-z0-9_-]{1,32})" >&2; exit 2; }; "$1" "${@:2}" ;;
  restart-watchdog) T respawn-pane -k -t jiva:watchdog -c "$TARGET" "$(wdcmd)" && echo "jiva: watchdog restarted ($SOCK)" ;;
  down) "$JIVA_HOME/core/dash.sh" stop >/dev/null 2>&1 || true; T kill-server 2>/dev/null || true; echo "jiva: down ($SOCK)" ;;
  roster) shift; exec "$JIVA_HOME/scripts/roster.sh" "${1:-check}" "${2:-default}" ;;
  status|doctor|dash|mine|spike|pick|watch|history|scratch|governor) c=$1; shift; exec "$JIVA_HOME/core/$c.sh" "$@" ;;
  pause|resume) exec "$JIVA_HOME/core/governor.sh" "$@" ;;
  check) cd "$TARGET" && exec "$JIVA_HOME/core/check.sh" ;;
  claim|unclaim|report|ask|answer|ship|handoff|inbox|pending) exec "$JIVA_HOME/core/verbs.sh" "$@" ;;
  ''|help|-h|--help) help ;;
  *) help >&2; exit 1 ;;
esac
