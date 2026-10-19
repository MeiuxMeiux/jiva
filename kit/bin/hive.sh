#!/usr/bin/env bash
# hive — cells on a PRIVATE tmux server (`tmux -L hive`), never your own tmux. Run from anywhere in the repo.
#   up                     watch window (bin/watch.sh); a fresh server first clears stale launch files + claims
#   add <cell> <card>      card → .hive/cards/<cell>.md (needs Area:/Owned paths:/Done-when:), lean claude window
#   ls                     cells: window state, card, tokens (from statusline json)
#   peek <cell> [n]        last n non-blank pane lines (default 30)
#   say <cell> <text>      type text into the cell (send-keys -l, then a separate Enter)
#   restart <cell>         kill the pane and boot a fresh body (it reads its handoff first)
#   stop <cell>            kill the window and forget the cell (watch stops relaunching it)
#   down                   kill the private server (your own tmux is untouched)
# Env: FLEET_SOCK (hive) · FLEET_MODEL (opus) · FLEET_CLAUDE (claude) · FLEET_ARGS (extra claude flags)
#      FLEET_LEAN=0 drops --strict-mcp-config · FLEET_TICK (60) watch interval.
set -euo pipefail
ROOT="${FLEET_ROOT:-$(git rev-parse --show-toplevel)}"; F="$ROOT/.hive"; S="$F/state"
SOCK="${FLEET_SOCK:-hive}"; HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# a tmux server started from inside claude leaks that session's identity into every pane
LEAKED="CLAUDECODE CLAUDE_PID CLAUDE_PROJECT_DIR CLAUDE_CODE_SESSION_ID CLAUDE_CODE_ENTRYPOINT CLAUDE_CODE_EXECPATH
  CLAUDE_CODE_CHILD_SESSION CLAUDE_CODE_MESSAGING_SOCKET CLAUDE_CODE_MESSAGING_TOKEN CLAUDE_CODE_SESSION_ATTENDED"
T() { tmux -L "$SOCK" "$@"; }
die() { echo "hive: $*" >&2; exit 1; }
seat_ok() { [[ ${1:-} =~ ^[A-Za-z0-9_-]{1,32}$ && $1 != watch ]] || die "bad cell name '${1:-}' ([A-Za-z0-9_-]{1,32}, not 'watch')"; }
live() { T has-session -t hive 2>/dev/null; }
has_win() { T list-windows -t hive -F '#W' 2>/dev/null | grep -qx "$1"; }

cmdline() { # cell → pane command: clean env, lean flags, boot prompt (handoff first if it exists)
  local lean="" p
  [[ ${FLEET_LEAN:-1} == 0 ]] || lean="--strict-mcp-config "
  p="Read .hive/roles/worker.md if it exists, then .hive/handoff/$1.md if it exists, then .hive/cards/$1.md. Work."
  # shellcheck disable=SC2086
  printf 'unset %s; cd %q && FLEET_ROOT=%q FLEET_NAME=%q FLEET_ROLE=worker FLEET_SOCK=%q %q %s--model %q --name %q %s %q' \
    "$(echo $LEAKED)" "$ROOT" "$ROOT" "$1" "$SOCK" "${FLEET_CLAUDE:-claude}" "$lean" "${FLEET_MODEL:-opus}" "$1" "${FLEET_ARGS:-}" "$p"
}

up() {
  mkdir -p "$S"/launch "$F"/cards "$F"/handoff
  if live; then echo "hive: already up (tmux -L $SOCK)"; return; fi
  rm -f "$S"/launch/* "$S"/claims "$S"/deaths/* "$S"/parked/*   # fresh server: last hive's cells stay down
  # shellcheck disable=SC2086
  unset $LEAKED
  T new-session -d -s hive -n watch -x 200 -y 50 -c "$ROOT" \
    "FLEET_ROOT=$(printf %q "$ROOT") FLEET_SOCK=$(printf %q "$SOCK") bash $(printf %q "$HERE/watch.sh"); exec bash"
  T set -g remain-on-exit on   # a cell that exits leaves a dead pane: watch relaunches it
  echo "hive: up (tmux -L $SOCK attach -t hive). Next: just hive add w1 .hive/cards/w1.md"
}

add() {
  local cell=${1:-} card=${2:-} k
  seat_ok "$cell"; [[ -s $card ]] || die "no card at '$card'"
  for k in 'Area:' 'Owned paths:' 'Done-when:'; do grep -q "^$k" "$card" || die "card lacks a '$k' line — goes back unstarted"; done
  grep -qE '^(Area|Owned paths|Done-when):.*<[^>]*>' "$card" && die "card still has template placeholders (<…>) — fill them in first"
  live || die "not up — run hive.sh up first"; has_win "$cell" && die "$cell already seated (restart or stop it)"
  [[ $(readlink -f "$card") == "$(readlink -f "$F/cards/$cell.md")" ]] || cp "$card" "$F/cards/$cell.md"
  echo "$cell" > "$S/launch/$cell"
  T new-window -d -t hive -n "$cell" -c "$ROOT" "$(cmdline "$cell")"
  echo "hive: $cell seated (card .hive/cards/$cell.md). First run in a repo: attach and accept the trust dialog once."
}

ls_() {
  live || { echo "hive: down"; return; }
  local f s st tok
  for f in "$S"/launch/*; do
    [[ -e $f ]] || continue; s=$(basename "$f")
    st=$(T list-panes -t "hive:$s" -F '#{?pane_dead,dead,live}' 2>/dev/null | head -1); st=${st:-gone}
    [[ -e $S/parked/$s ]] && st="parked"
    tok=$(jq -r '.tok // 0' "$S/$s.json" 2>/dev/null || echo 0)
    printf '%-10s %-7s %4sk  %s\n' "$s" "$st" "$(( ${tok%.*} / 1000 ))" "$(grep -m1 '^Area:' "$F/cards/$s.md" 2>/dev/null)"
  done
}

peek() { seat_ok "${1:-}"; T capture-pane -p -t "hive:$1" -S -200 | grep -v '^[[:space:]]*$' | tail -n "${2:-30}"; }
say() {
  seat_ok "${1:-}"; [[ -n ${2:-} ]] || die "say <cell> <text>"; has_win "$1" || die "no cell $1"
  T send-keys -t "hive:$1" -l "$2"; sleep 0.3; T send-keys -t "hive:$1" Enter
}
restart() { seat_ok "${1:-}"; has_win "$1" || die "no cell $1"; T respawn-pane -k -t "hive:$1" -c "$ROOT" "$(cmdline "$1")"; echo "hive: $1 restarted"; }
stop() { seat_ok "${1:-}"; rm -f "$S/launch/$1"; T kill-window -t "hive:$1" 2>/dev/null || true; echo "hive: $1 stopped"; }
down() { T kill-server 2>/dev/null || true; echo "hive: down (tmux -L $SOCK)"; }

[[ ${BASH_SOURCE[0]} == "$0" ]] || return 0
cmd=${1:-help}; shift || true
case $cmd in
  up|add|peek|say|restart|stop|down) "$cmd" "$@" ;;
  ls) ls_ ;;
  cmdline) seat_ok "${1:-}"; cmdline "$1"; echo ;;
  *) sed -n '2,/^set -euo/p' "${BASH_SOURCE[0]}" | sed '$d; s/^# \{0,1\}//'; [[ $cmd == help ]] ;;
esac
