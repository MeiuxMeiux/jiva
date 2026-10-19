#!/usr/bin/env bash
# doctor-lease — queen lease against a scratch TARGET in /tmp + its own tmux socket (jiva-jiva-doctor-*,
# never the live hive): (a) fresh lease + 2nd queen → refused, extra pane killed; same-pane respawn takes
# over; (b) stale lease → flags/lease-stale, one toast; (c) refresh → flag cleared; (d) no lease + no queen →
# JIVA_DRY=1 prints the spawn; parked → nothing; (f) dogfood P2/P9 target + init. Prints ok/FAIL; exit 1 on any FAIL.
set -uo pipefail
H="$(cd "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")/.." && pwd)"
S="$(mktemp -d /tmp/jiva-doctor-XXXXXX)"
# shellcheck source=core/lib.sh
JIVA_TARGET="$S" source "$H/core/lib.sh"
trap 'T kill-server 2>/dev/null; rm -rf "$S"' EXIT
JV="$H/core/jiva.sh"; JIVA_LEASE_TTL=90 JIVA_LEASE_GRACE=0
toast() { echo "toast $*"; }
# shellcheck source=core/lease.sh
source "$H/core/lease.sh"
bad=0
ok() { printf 'ok    lease %s\n' "$1"; }
no() { printf 'FAIL  lease %s\n' "$1"; bad=1; }
t() { local l=$1; shift; if "$@"; then ok "$l"; else no "$l"; fi; }
hook() { # script sid pane → run a hook as a queen-named session (pane "" = outside our socket)
  local tm=() ; [[ -n $3 ]] && tm=(TMUX="/x/$SOCK,1,0" TMUX_PANE="$3")
  printf '{"session_id":"%s","context_window":{"total_input_tokens":1}}' "$2" |
    env -u TMUX -u TMUX_PANE "${tm[@]}" CLAUDE_PROJECT_DIR="$S" JIVA_ROLE=queen JIVA_NAME=queen \
      "$H/core/hooks/$1.sh"
}
pane() { T list-panes -a -F '#{pane_id} #W' | awk -v w="$1" '$2 == w { print $1; exit }'; }
has() { T list-panes -a -F '#{pane_id}' | grep -qx "$1"; }
holder() { read -r _ sid _ < "$LEASE"; echo "$sid"; }

T new-session -d -s jiva -n queen -x 80 -y 20 'sleep 600'
T new-window -d -t jiva -n x 'sleep 600'; T split-window -d -t jiva:queen 'sleep 600'
P1=$(pane queen); PX=$(pane x); PS=$(T list-panes -t jiva:queen -F '#{pane_id}' | grep -vx "$P1")

# (a) first queen takes the lease; a second queen (other sid, other pane) is refused and killed
hook session-start s-1 "$P1" >/dev/null
t "first queen takes the lease" test "$(holder)" = s-1
out="$(hook session-start s-2 "$PX" | jq -r .hookSpecificOutput.additionalContext)"
t "2nd queen told 'lease held by s-1'" grep -q '^lease held by s-1' <<<"$out"
t "2nd queen did not take it" test "$(holder)" = s-1
hook statusline s-2 "$PX" >/dev/null
t "2nd queen statusline cannot steal it" test "$(holder)" = s-1
t "refused pane recorded as extra" test -e "$J/lease/extra.$PX"
lease_tick >/dev/null
t "watchdog kills the extra pane" bash -c "! tmux -L '$SOCK' list-panes -a -F '#{pane_id}' | grep -qx '$PX'"
t "watchdog kills a stray pane in the queen window" bash -c "! tmux -L '$SOCK' list-panes -a -F '#{pane_id}' | grep -qx '$PS'"
t "lease holder pane untouched" has "$P1"
hook session-start s-3 "$P1" >/dev/null
t "respawn in the same pane takes over" test "$(holder)" = s-3

# (b) stale lease (> 3×TTL) with the queen pane live → flag + one toast
echo "$(( $(date +%s) - 3 * 90 - 10 )) s-3 $P1" > "$LEASE"
t "state stale" test "$(lease_state)" = stale
o1="$(lease_tick)"; o2="$(lease_tick)"
t "stale → flags/lease-stale" test "$(cat "$J/flags/lease-stale" 2>/dev/null)" = stale
t "stale toasts once" test "$(grep -c 'toast queen lease stale' <<<"$o1$o2")" = 1

# (c) the queen statusline refreshes → fresh, flag cleared
hook statusline s-3 "$P1" >/dev/null; lease_tick >/dev/null
t "refresh → state fresh" test "$(lease_state)" = fresh
t "refresh clears the flag" test ! -e "$J/flags/lease-stale"

# (e) regression (12c0698): `jiva doctor` run from inside a worker pane never touches the live lease
T new-window -d -t jiva -n w1 'sleep 600'; PW=$(pane w1); before="$(cat "$LEASE")"
TMUX="/x/$SOCK,1,0" TMUX_PANE="$PW" JIVA_TARGET="$S" "$H/core/doctor.sh" payload >/dev/null
t "doctor in a worker pane writes no lease/extra.*" test -z "$(find "$J/lease" -name 'extra.*')"
t "doctor in a worker pane leaves the lease as is" test "$(cat "$LEASE")" = "$before"

# (f) dogfood P2/P9: an inherited pane TARGET yields to $PWD's repo; init says what it left uncommitted
R="$S/repo"; P="$S/pane"; git init -q "$R"; mkdir -p "$P"; lt() { (cd "$R" && env "$@" bash -c "source '$H/core/lib.sh'; echo \"\$TARGET\""); }
t "P2: pane-inherited JIVA_TARGET yields to PWD's repo" test "$(lt JIVA_TARGET="$P" JIVA_PANE_TARGET="$P")" = "$(realpath "$R")"
t "P2: explicit JIVA_TARGET still wins" test "$(lt JIVA_TARGET="$P" JIVA_PANE_TARGET=/x)" = "$(realpath "$P")"
t "P9: init says .gitignore + CLAUDE.md left uncommitted" grep -q 'uncommitted.*CLAUDE.md\|CLAUDE.md.*uncommitted' \
  <<<"$(cd "$R" && env -u JIVA_PANE_TARGET -u JIVA_TARGET "$JV" init 2>&1)"

# (d) no lease + no queen → heal would spawn (dry run); parked → nothing
T kill-window -t jiva:queen; rm -f "$LEASE"
t "state none" test "$(lease_state)" = none
t "no queen → would spawn queen" grep -q "would $JV spawn queen queen" <<<"$(JIVA_DRY=1 lease_tick)"
mkdir -p "$J/parked"; touch "$J/parked/queen"
t "parked queen → no spawn" test -z "$(JIVA_DRY=1 lease_tick)"
exit $bad
