# notify — portable alerts (core/notify.sh, sourced)
- `toast <text>`: always appends `<epoch> <text>` to `$J/notify.log` (last JIVA_NOTIFY_KEEP=200 lines kept;
  newlines flattened), then one desktop ping. Never fails the caller (set -e safe), never blocks: backend
  runs detached `( timeout … & )`.
- Backend, first match: WSL (`/proc/version` has microsoft, or JIVA_NOTIFY_WSL=1) + `powershell.exe` → balloon
  (timeout JIVA_NOTIFY_PS_SECS=12, it sleeps 9s to stay visible; `'` doubled) · `notify-send` · `osascript`
  (text via argv, no quoting) · else `\a` to stdout (the watchdog pane). JIVA_NOTIFY_WSL=0 forces non-WSL.
- Knobs: JIVA_NOTIFY=off (log only) · JIVA_NOTIFY_SECS=2 (notify-send/osascript cut-off) · _KEEP · _PS_SECS.
- No `timeout` (stock macOS) → runs unbounded but still detached.
- If `$J` is unset when sourced, notify.sh sources lib.sh itself.
- Consumers: watchdog.sh (w2 swaps its toast() for `source core/notify.sh`); watch.sh ALERTS line reads the log.
- Test: `jiva doctor notify` (core/doctor-notify.sh): scratch J + PATH of symlinked tools + stub backends + stub curl, 22 checks.
- ntfy: JIVA_NOTIFY_NTFY=<https://ntfy.sh/topic or self-hosted url> → also `curl -m 5` POST of the text, title
  `jiva`, detached, after the log line and the desktop ping (JIVA_NOTIFY=off skips it too). Unset = no network.
  The url (may carry a token) goes to curl via `-K -` stdin — never on argv, never echoed; curl output → /dev/null.
