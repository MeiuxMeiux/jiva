#!/usr/bin/env bash
# spike helpers — all tmux traffic goes to the dedicated `jiva` server, never the human's.
set -euo pipefail
T() { tmux -L jiva "$@"; }
ROOT="$(git -C "$(dirname "${BASH_SOURCE[0]}")" rev-parse --show-toplevel)"

# spawn <name> [claude args...] — new window running claude in the repo root
spawn() {
  local name=$1; shift
  T has-session -t jiva 2>/dev/null || T new-session -d -s jiva -n shell -x 200 -y 50 -c "$ROOT"
  T new-window -d -t jiva -n "$name" -c "$ROOT" \
    "JIVA_ROLE=spike claude --model haiku --name $name $(printf '%q ' "$@"); exec bash"
}
# screen <name> — dump visible pane text
screen() { T capture-pane -p -t "jiva:$1"; }
# say <name> <text> — type a prompt and submit
say() { T send-keys -t "jiva:$1" -l "$2"; sleep 0.3; T send-keys -t "jiva:$1" Enter; }
# waitfor <name> <regex> [secs] — block until pane text matches
waitfor() {
  local n=${3:-60}
  for ((i = 0; i < n; i++)); do screen "$1" | grep -qE "$2" && return 0; sleep 1; done
  echo "timeout waiting for /$2/ in $1" >&2; return 1
}
# kill_spike — tear down the whole jiva tmux server
kill_spike() { T kill-server 2>/dev/null || true; }
