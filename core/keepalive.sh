#!/usr/bin/env bash
# keepalive — a hidden Windows-side wsl.exe holds the distro up so the jiva tmux server survives
# closing Windows Terminal. Lasts until reboot. Human-run (`! just keepalive`); auto mode won't start it.
set -euo pipefail
running() { pgrep -f '^jiva-keepalive' >/dev/null; }
case "${1:-start}" in
  start)
    running && { echo "keepalive: already up"; exit 0; }
    # Start-Process joins args with bare spaces, so pass no arg containing a space
    powershell.exe -NoProfile -Command "Start-Process -WindowStyle Hidden wsl.exe -ArgumentList \
'-d','${WSL_DISTRO_NAME:?not in WSL}','--exec','$(realpath "$0")','hold'" | tr -d '\r'
    for _ in 1 2 3 4 5 6 7 8; do running && { echo "keepalive: up"; exit 0; }; sleep 1; done
    echo "keepalive: failed to start" >&2; exit 1 ;;
  hold) exec -a jiva-keepalive sleep infinity ;;   # what the Windows side runs
  stop) pkill -f '^jiva-keepalive' && echo "keepalive: stopped" || echo "keepalive: not running" ;;
  status) running && echo up || { echo down; exit 1; } ;;
esac
