#!/usr/bin/env bash
# doctor-fault — fault injection against a scratch TARGET (/tmp/jiva-doctor-*) on its own tmux socket, never
# the live fleet. `claude` is a stub on PATH (prints the ready prompt, `agents` lists the boss), so nothing
# boots for real and no trust dialog appears. One function per fault; each must self-heal or raise a flag:
#   disk     ulimit -f 0 → one flags/disk-full, one log line (no error loop); cleared once writable
#   quota    statusline rate_limits 87% → flags/quota + reason; spawn and assign refuse
#   wd       kill -9 the watchdog → status "watchdog dead", bar red; restart-watchdog heals it
#   tmux     kill-server → status "runtime down", never "lease fresh"; `jiva up 0` recovers
#   state    state.json truncated/invalid → status never crashes; the watchdog rewrites it next tick
#   trust    a window at the trust dialog → status "1 at trust dialog" (dogfood P8)
#   governor pause → no heal/lease/rotation, one handoff say ≥95%, PAUSED prefix; JIVA_FLEET_USD auto-pause
#   auth     a pane tail with "API Error" → flags/<n>-auth, one toast; cleared once the text is gone
# Prints ok/FAIL; exit 1 on any FAIL. No tmux → one skipped ok line.
set -uo pipefail
H="$(cd "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")/.." && pwd)"
command -v tmux >/dev/null || { echo "ok    fault: tmux unavailable (skipped)"; exit 0; }
S="$(mktemp -d /tmp/jiva-doctor-XXXXXX)"
# shellcheck source=core/lib.sh
JIVA_TARGET="$S" source "$H/core/lib.sh"
trap 'T kill-server 2>/dev/null; rm -rf "$S"' EXIT
mkdir -p "$S/stub" "$J/state"
cat > "$S/stub/claude" <<'SH'
#!/usr/bin/env bash
[[ ${1:-} == agents ]] && { jq -nc --arg c "$JIVA_TARGET" '[{name: "boss", cwd: $c, status: "idle", startedAt: (now * 1000)}]'; exit; }
echo "? for agents"; exec sleep 600
SH
chmod +x "$S/stub/claude"
export PATH="$S/stub:$PATH" JIVA_TARGET="$S" JIVA_HOOKS=settings JIVA_TICK=1 JIVA_DRY=1 JIVA_WD_STALE=4
JV="$H/core/jiva.sh"; ST="$H/core/status.sh"; bad=0
ok() { printf 'ok    fault %s\n' "$1"; }
no() { printf 'FAIL  fault %s\n' "$1"; bad=1; }
t() { local l=$1; shift; if "$@"; then ok "$l"; else no "$l"; fi; }
ticks() { # n [pre-command…] → run n watchdog ticks in a subshell (toasts → stdout: ulimit spares pipes), no tmux
  local n=$1; shift
  ( "$@"; source "$H/core/watchdog.sh"; toast() { echo "toast $*"; }
    for _ in $(seq "$n"); do tick; done ) 2>&1
}
fresh() { local a; for _ in $(seq "${1:-10}"); do a="$(jq -r '.ts // 0' "$J/state.json" 2>/dev/null || echo 0)"
  (( $(date +%s) - a <= 2 )) && return 0; sleep 1; done; return 1; }
wdpid() { pgrep -P "$(T list-panes -t jiva:watchdog -F '#{pane_pid}' 2>/dev/null || echo 0)" -f watchdog.sh; }

disk() {
  local out; out="$(ticks 3 eval "trap '' XFSZ; ulimit -f 0")"
  t "disk: full → flags/disk-full" test -e "$J/flags/disk-full"
  t "disk: one log line over 3 ticks (no loop)" test "$(grep -c 'flagged disk-full' <<<"$out")" = 1
  t "disk: one toast" test "$(grep -c 'toast jiva: disk full' <<<"$out")" = 1
  ticks 1 >/dev/null
  t "disk: writable again → flag cleared, state.json written" bash -c "[[ ! -e '$J/flags/disk-full' ]] && jq -e .ts '$J/state.json' >/dev/null"
}

quota() {
  printf '{"session_id":"q","rate_limits":{"five_hour":{"used_percentage":87}}}' |
    CLAUDE_PROJECT_DIR="$S" JIVA_NAME=w5 "$H/core/hooks/statusline.sh" >/dev/null
  local out; out="$(ticks 2)"
  t "quota: 87% → flags/quota with reason" grep -q '5h 87%' "$J/flags/quota"
  t "quota: one toast over 2 ticks" test "$(grep -c 'toast jiva: quota at 87%' <<<"$out")" = 1
  local o rc; o="$("$JV" spawn worker w6 2>&1)"; rc=$?
  t "quota: spawn refused with reason" bash -c "(( $rc != 0 )) && grep -q 'quota at 87%' <<<'$o'"
  printf 'task\n' > "$S/card.md"
  t "quota: assign refused" bash -c "! '$JV' assign w6 '$S/card.md' >/dev/null 2>&1"
  t "quota: no worker window started" bash -c "! tmux -L '$SOCK' list-windows -t jiva -F '#W' 2>/dev/null | grep -qx w6"
  rm -f "$J/state/w5.json"; ticks 1 >/dev/null
  t "quota: below cap → flag cleared" test ! -e "$J/flags/quota"
}

wd() {
  local p; p="$(wdpid)"; [[ -n $p ]] || { no "wd: no watchdog process in the scratch pane"; return; }
  t "wd: status-right runs status.sh bar" grep -q 'status.sh.* bar' <<<"$(T show -gv status-right)"
  kill -9 "$p"; sleep 6
  t "wd: kill -9 → status says watchdog dead" grep -q 'watchdog dead' <<<"$("$ST" 2>&1)"
  t "wd: status hides the lease state" bash -c "! '$ST' 2>&1 | grep -q 'lease fresh'"
  t "wd: bar goes red" grep -q 'bg=red.*watchdog dead' <<<"$("$ST" bar)"
  "$JV" restart-watchdog >/dev/null
  t "wd: restart-watchdog → state fresh again" fresh 10
  t "wd: bar back to normal" bash -c "! '$ST' bar | grep -q 'watchdog dead'"
}

server_death() {
  mkdir -p "$J/lease"; echo "$(date +%s) s-1 %0" > "$J/lease/boss"; T kill-server
  local out; out="$("$ST" 2>&1)"
  t "tmux: dead → status says runtime down" grep -q 'runtime down' <<<"$out"
  t "tmux: lease not reported fresh" bash -c "! grep -q 'lease fresh' <<<'$out'"
  t "tmux: jiva up 0 recovers" bash -c "'$JV' up 0 >/dev/null 2>&1 && tmux -L '$SOCK' has-session -t jiva"
  t "tmux: watchdog ticking after up" fresh 10
}

state() { # status/bar read a quiet scratch target (no watchdog to race), then the live tick must rewrite
  local q="$S/q" o; mkdir -p "$q/.jiva"
  for js in '{"ts":' ''; do printf %s "$js" > "$q/.jiva/state.json"
    o="$(JIVA_TARGET="$q" "$ST" 2>&1)"; local rc=$?
    t "state: ${js:-truncated} → status names state.json, rc ≤1, no bash error" bash -c \
      "(( $rc <= 1 )) && grep -q 'state.json' <<<\"\$1\" && ! grep -qE 'line [0-9]+:|syntax error' <<<\"\$1\"" _ "$o"
  done
  printf '{"ts":' > "$q/.jiva/state.json"
  t "state: invalid → status says unreadable" grep -q 'unreadable' <<<"$(JIVA_TARGET="$q" "$ST" 2>&1)"
  t "state: invalid → bar does not crash" bash -c "JIVA_TARGET='$q' '$ST' bar >/dev/null"
  printf '{"ts":' > "$J/state.json"; t "state: invalid → rewritten next tick" fresh 5
  : > "$J/state.json"; t "state: truncated → rewritten next tick" fresh 5
  printf '{"tok":' > "$J/state/bad.json"
  t "state: a corrupt per-session file does not stop the tick" bash -c "sleep 2; jq -e '.ts > $(date +%s)' '$J/state.json' >/dev/null"
  rm -f "$J/state/bad.json"
}

wsh() { # code → run it after sourcing the watchdog (no loop), toast/say/heal/lease stubbed to stdout
  ( source "$H/core/watchdog.sh"; toast() { echo "toast $*"; }; heal() { echo HEAL; }; lease_tick() { echo LEASE; }
    JV="$S/stub/jv"; eval "$1" ) 2>&1
}
governor() { # pause: no heal/lease/rotation, one handoff say ≥95%; fleet $ cap auto-pauses once
  local G="$H/core/governor.sh" out; printf '#!/usr/bin/env bash\necho "jv $*"\n' > "$S/stub/jv"; chmod +x "$S/stub/jv"
  mkdir -p "$J"/{launch,rotate,parked,flags}; echo worker > "$J/launch/boss"; touch "$J/rotate/boss"; echo '{"tok":196000,"usd":1}' > "$J/state/boss.json"
  "$G" pause doctor >/dev/null
  t "gov: pause → status line 1 PAUSED · " grep -q '^PAUSED · ' <<<"$("$ST" 2>&1)"
  out="$(wsh 'tick; tick')"
  t "gov: paused → no heal, no lease_tick, no rotation respawn" bash -c "! grep -qE 'HEAL|LEASE|jv respawn' <<<\"\$1\"" _ "$out"
  t "gov: paused ≥95% → one handoff-now say" test "$(grep -c 'handoff now' <<<"$out")" = 1
  t "gov: bar PAUSED" grep -q '^PAUSED · ' "$J/bar"
  rm -f "$J/parked/boss"; echo '{"tok":1000}' > "$J/state/boss.json"   # the storm breaker parked it
  "$G" resume >/dev/null; out="$(wsh tick)"
  t "gov: resume → heal + lease_tick + rotation again" bash -c "grep -q HEAL <<<\"\$1\" && grep -q LEASE <<<\"\$1\" && grep -q 'jv respawn boss' <<<\"\$1\"" _ "$out"
  rm -f "$J"/{parked,flags,rotate}/boss "$J"/nudged/boss*; echo '{"tok":1000,"usd":6}' > "$J/state/boss.json"
  out="$(JIVA_FLEET_USD=5 wsh 'tick; tick')"
  t "gov: fleet \$6 ≥ cap 5 → paused + flags/fleet-usd" bash -c "grep -q fleet '$J/paused' && test -e '$J/flags/fleet-usd'"
  local nt nh; nt=$(grep -c 'toast jiva: fleet' <<<"$out"); nh=$(grep -c '"governor".*"pause"' "$J/history.jsonl")
  t "gov: cap → one toast, one hist pause (+1 by hand)" test "$nt $nh" = "1 2"
  "$G" resume >/dev/null; JIVA_FLEET_USD=5 wsh tick >/dev/null
  t "gov: resume clears pause + flag, cap does not re-pause" bash -c "[[ ! -e '$J/paused' && ! -e '$J/flags/fleet-usd' ]]"
  rm -f "$J/state/boss.json" "$J/governor.capped" "$J"/nudged/boss*
}

auth() { # a pane tail with "API Error" → flags/<n>-auth + one toast; text gone → cleared
  T new-window -d -t jiva -n w8 "printf 'API Error: 529 overloaded\n'; exec sleep 600"; sleep 1
  local out; out="$(wsh 'auth w8; auth w8')"
  t "auth: API Error in pane → flags/w8-auth" grep -q 'API Error' "$J/flags/w8-auth"
  t "auth: one toast over 2 checks" test "$(grep -c '^toast w8' <<<"$out")" = 1
  T respawn-pane -k -t jiva:w8 "echo all good; exec sleep 600"; sleep 1; wsh 'auth w8' >/dev/null
  t "auth: text gone → flag cleared" test ! -e "$J/flags/w8-auth"; T kill-window -t jiva:w8
}

trust() { # dogfood P8: a pane parked at the trust dialog is not "live" — status + bar must say so
  T new-window -d -t jiva -n w7 "echo 'Do you trust this folder?'; exec sleep 600"; sleep 3
  t "trust: status says 1 at trust dialog" grep -q '1 at trust dialog' <<<"$("$ST" 2>&1)"
  T kill-window -t jiva:w7
}

case "${1:-all}" in
  all) disk; quota; governor; "$JV" up 0 >/dev/null 2>&1 || no "setup: jiva up 0 on the scratch socket"
       fresh 10 || no "setup: scratch watchdog never wrote state.json"; wd; server_death; state; trust; auth ;;
  *) "$1" ;;
esac
exit $bad
