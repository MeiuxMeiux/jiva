#!/usr/bin/env bash
# doctor-notify — core/notify.sh against a scratch J in /tmp and a scratch PATH (only stub backends + the tools
# notify.sh needs, so the real powershell.exe/notify-send never fire): backend pick per environment (WSL faked
# with JIVA_NOTIFY_WSL), log line written + capped, JIVA_NOTIFY=off skips the desktop, a hanging backend is
# cut at 2s and never blocks the caller, an unwritable log never fails it; JIVA_NOTIFY_NTFY → one stub curl. Prints ok/FAIL; exit 1 on any FAIL.
set -uo pipefail
H="$(cd "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")/.." && pwd)"
S="$(mktemp -d /tmp/jiva-doctor-XXXXXX)"; export J="$S/.jiva"
trap 'pkill -f "$S/"  2>/dev/null; rm -rf "$S"' EXIT
bad=0
ok() { printf 'ok    notify %s\n' "$1"; }
no() { printf 'FAIL  notify %s\n' "$1"; bad=1; }
mkdir -p "$S/sys" "$S/stub"
for c in bash sh date wc tail mv mkdir grep timeout sleep cat dirname readlink; do ln -s "$(command -v "$c")" "$S/sys/$c"; done
for b in powershell.exe notify-send osascript; do   # stub: record the call; NOTIFY_HANG=1 → hang 30s
  printf '#!/bin/sh\necho "%s $*" >> "%s/calls"\n[ -n "$NOTIFY_HANG" ] && sleep 30\nexit 0\n' "$b" "$S" > "$S/stub/$b"
  chmod +x "$S/stub/$b"
done
# stub curl: record argv + the -K config from stdin; CURL_FAIL=1 → exit 22
printf '#!/bin/sh\necho "curl $* | $(cat)" >> "%s/ccalls"\n[ -n "$CURL_FAIL" ] && exit 22\nexit 0\n' "$S" > "$S/stub/curl"
chmod +x "$S/stub/curl"
P="$S/sys"
run() { # "stubs to expose" cmd… → run with only those backends on PATH (fresh bash, notify.sh sourced)
  local d="$S/p$RANDOM" b; mkdir -p "$d"; for b in $1; do ln -s "$S/stub/$b" "$d/$b"; done; shift
  PATH="$d:$P" "$S/sys/bash" -c "source '$H/core/notify.sh'; $*"
}
pick() { local got; got="$(JIVA_NOTIFY_WSL=$2 run "$3" notify_backend)"
  [[ $got == "$4" ]] && ok "$1 → $4" || no "$1 → got '$got', want $4"; }
pick "WSL + powershell.exe" 1 "powershell.exe notify-send osascript" powershell
pick "Linux (not WSL) ignores powershell.exe" 0 "powershell.exe notify-send osascript" notify-send
pick "WSL without powershell.exe" 1 "notify-send" notify-send
pick "macOS (osascript only)" 0 "osascript" osascript
pick "no backend" 0 "" bell
calls() { for _ in 1 2 3 4 5 6 7 8 9 10; do [[ -s $S/calls ]] && break; sleep 0.1; done; cat "$S/calls" 2>/dev/null; }

: > "$S/calls"; JIVA_NOTIFY_WSL=0 run notify-send 'toast "worker w3 parked"'
[[ $(calls) == "notify-send JIVA worker w3 parked" ]] && ok "notify-send called with the text" || no "calls: $(calls)"
grep -qE '^[0-9]+ worker w3 parked$' "$J/notify.log" && ok "log line '<epoch> <text>' written" || no "log: $(cat "$J/notify.log")"
: > "$S/calls"; JIVA_NOTIFY_WSL=1 run powershell.exe "toast \"it's w2\""
grep -qF "'JIVA','it''s w2'" <<<"$(calls)" && ok "powershell balloon, quote escaped" || no "ps call: $(calls)"
: > "$S/calls"; JIVA_NOTIFY=off JIVA_NOTIFY_WSL=0 run notify-send 'toast "quiet one"'; sleep 0.5
[[ ! -s $S/calls ]] && ok "JIVA_NOTIFY=off skips the desktop call" || no "off still called: $(cat "$S/calls")"
[[ $(tail -n 1 "$J/notify.log") == *" quiet one" ]] && ok "JIVA_NOTIFY=off still logs" || no "off did not log"
JIVA_NOTIFY_KEEP=5 JIVA_NOTIFY=off run "" 'for i in 1 2 3 4 5 6 7 8; do toast "n$i"; done'
[[ $(wc -l < "$J/notify.log") == 5 && $(tail -n 1 "$J/notify.log") == *" n8" ]] && ok "log capped to KEEP, newest kept" ||
  no "cap: $(wc -l < "$J/notify.log") lines, last '$(tail -n 1 "$J/notify.log")'"
grep -qF 'JIVA_NOTIFY_KEEP:-200' "$H/core/notify.sh" && ok "default cap 200" || no "default cap not 200"

: > "$S/calls"; t0=$(date +%s%N)
NOTIFY_HANG=1 JIVA_NOTIFY_WSL=0 run notify-send 'toast "hang"; echo rc=$?' > "$S/out"
ms=$(( ($(date +%s%N) - t0) / 1000000 ))
(( ms < 1000 )) && ok "hanging backend doesn't block the caller (${ms}ms)" || no "caller blocked ${ms}ms"
grep -qx 'rc=0' "$S/out" && ok "toast returns 0" || no "toast rc: $(cat "$S/out")"
calls >/dev/null; pgrep -f "$S/p[0-9]*/notify-send" >/dev/null && ok "backend running before the cut" || no "backend never started"
sleep 2.5; pgrep -f "$S/p[0-9]*/notify-send" >/dev/null && no "hanging backend alive after 2.5s" || ok "hanging backend cut at 2s"

cc() { for _ in 1 2 3 4 5 6 7 8 9 10; do [[ -s $S/ccalls ]] && break; sleep 0.1; done; cat "$S/ccalls" 2>/dev/null; }
: > "$S/ccalls"; JIVA_NOTIFY_WSL=0 run "notify-send curl" 'toast "no ntfy"'; sleep 0.5
[[ ! -s $S/ccalls ]] && ok "ntfy unset → no curl call" || no "unset still called curl: $(cat "$S/ccalls")"
: > "$S/ccalls"; : > "$S/calls"; U="https://ntfy.example/tk_SECRET/topic"
JIVA_NOTIFY_NTFY="$U" JIVA_NOTIFY_WSL=0 run "notify-send curl" 'toast "w3 shipped"' > "$S/out" 2>&1
c="$(cc)"; [[ $(grep -c '^curl ' <<<"$c") == 1 && $c == *"-m 5"*"Title: jiva"*"w3 shipped | url = \"$U\""* ]] &&
  ok "ntfy set → one curl POST with the text, -m 5, title jiva" || no "ntfy call: $c"
[[ ${c%% | *} != *tk_SECRET* && ! -s $S/out ]] && ok "ntfy url kept off argv and output" || no "url leaked: $c / $(cat "$S/out")"
[[ $(calls) == "notify-send JIVA w3 shipped" ]] && ok "ntfy runs in addition to the desktop" || no "desktop: $(calls)"
: > "$S/ccalls"; out="$(CURL_FAIL=1 JIVA_NOTIFY_NTFY="$U" JIVA_NOTIFY_WSL=0 run "notify-send curl" 'set -e; toast "boom"; echo rc=$?' 2>&1)"
[[ $out == rc=0 && -n $(cc) ]] && ok "curl failure → caller still exits 0" || no "curl fail: $out"

out="$(J=/proc/nope/.jiva JIVA_NOTIFY=off run "" 'set -e; toast "x"; echo alive' 2>&1)"
[[ $out == alive ]] && ok "unwritable log never fails a set -e caller" || no "unwritable log: $out"
exit $bad
