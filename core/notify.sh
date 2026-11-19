# shellcheck shell=bash
# notify — sourced; `toast <text>`: append `<epoch> <text>` to $J/notify.log (last 200 lines kept), then
# best-effort desktop ping, first match wins: WSL + powershell.exe balloon · notify-send · osascript · bell.
# Never fails the caller and never blocks: the backend runs detached under `timeout` (2s; the WSL balloon
# gets ${JIVA_NOTIFY_PS_SECS:-12}s since it must stay alive ~9s to be seen). Knobs:
#   JIVA_NOTIFY=off       log only, no desktop call       JIVA_NOTIFY_WSL=0|1   override /proc/version sniff
#   JIVA_NOTIFY_SECS=2    backend cut-off                 JIVA_NOTIFY_KEEP=200  log lines kept
#   JIVA_NOTIFY_NTFY=<url> also POST the text to ntfy (curl -m 5, detached; url fed via stdin, never echoed)
if [[ -z ${J:-} ]]; then
  # shellcheck source=core/lib.sh
  source "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")/lib.sh"
fi

notify_wsl() { # 0 when this is WSL (override with JIVA_NOTIFY_WSL=0|1)
  case "${JIVA_NOTIFY_WSL:-}" in 1) return 0 ;; 0) return 1 ;; esac
  grep -qi microsoft /proc/version 2>/dev/null
}

notify_backend() { # → powershell|notify-send|osascript|bell
  if notify_wsl && command -v powershell.exe >/dev/null 2>&1; then echo powershell
  elif command -v notify-send >/dev/null 2>&1; then echo notify-send
  elif command -v osascript >/dev/null 2>&1; then echo osascript
  else echo bell; fi
}

notify_log() { # text → append + cap; errors swallowed (disk full must not loop the watchdog)
  local log="$J/notify.log" keep="${JIVA_NOTIFY_KEEP:-200}"
  {
    mkdir -p "$J" && printf '%s %s\n' "$(date +%s)" "${1//$'\n'/ }" >> "$log" || return 0
    if (( $(wc -l < "$log") > keep )); then tail -n "$keep" "$log" > "$log.tmp" && mv "$log.tmp" "$log"; fi
  } 2>/dev/null
  return 0
}

notify_to() { # secs cmd… → `timeout` when present (stock macOS lacks it; still detached, so never blocks)
  if command -v timeout >/dev/null 2>&1; then timeout "$@"; else shift; "$@"; fi
}

notify_desktop() { # text → one backend, detached + time-boxed
  local t="$1" s="${JIVA_NOTIFY_SECS:-2}"
  case "$(notify_backend)" in
    powershell)
      t="${t//‘/\'}"; t="${t//’/\'}"; t="${t//‚/\'}"; t="${t//‛/\'}"   # PowerShell quotes with these too
      t="${t//\'/\'\'}"
      ( notify_to "${JIVA_NOTIFY_PS_SECS:-12}" powershell.exe -NoProfile -Command \
        "Add-Type -AssemblyName System.Windows.Forms;
        \$n=New-Object System.Windows.Forms.NotifyIcon; \$n.Icon=[System.Drawing.SystemIcons]::Information;
        \$n.Visible=\$true; \$n.ShowBalloonTip(8000,'JIVA','$t','Warning'); Start-Sleep 9; \$n.Dispose()" \
        >/dev/null 2>&1 & ) ;;
    notify-send) ( notify_to "$s" notify-send JIVA "$t" >/dev/null 2>&1 & ) ;;
    osascript)
      ( notify_to "$s" osascript -e 'on run argv' -e 'display notification (item 1 of argv) with title "JIVA"' \
        -e 'end run' -- "$t" >/dev/null 2>&1 & ) ;;
    bell) printf '\a' 2>/dev/null ;;   # the watchdog's stdout is its pane
  esac
  return 0
}

notify_ntfy() { # text → POST to $JIVA_NOTIFY_NTFY (may carry a token: kept off argv/output). Unset = no call.
  local u="${JIVA_NOTIFY_NTFY:-}"
  [[ -n $u ]] && command -v curl >/dev/null 2>&1 || return 0
  ( printf 'url = "%s"\n' "${u//\"/}" | curl -K - -s -m 5 -o /dev/null -H 'Title: jiva' --data-raw "$1" \
    >/dev/null 2>&1 & ) 2>/dev/null
  return 0
}

toast() { # text → log always; desktop + ntfy (when set) unless JIVA_NOTIFY=off. Always returns 0.
  notify_log "$*"
  [[ ${JIVA_NOTIFY:-on} == off ]] && return 0
  notify_desktop "$*"; notify_ntfy "${*//$'\n'/ }"
  return 0
}
