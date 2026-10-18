#!/usr/bin/env bash
# watch — zero-token bash loop (no model). Every FLEET_TICK (60) s, for each seat fleet.sh launched:
#   dead pane / missing window → relaunch; 3 deaths in 60 s = crash loop → parked, alert, no more relaunches
#   permission/trust dialog on screen → one alert per stall (a seat on a prompt looks busy)
#   statusline tokens ≥ FLEET_NUDGE (150k) → one say: hand off and exit; ≥ FLEET_ALERT (185k) → one alert
# Alerts append to .fleet/state/alerts.log. `watch.sh once` runs a single tick; `.fleet/state/STOP` ends the loop.
# `watch.sh digest`: the desk's timer tick — prints only items changed since the last run, NOTHING when quiet.
# Unpark a seat: rm .fleet/state/parked/<seat> (or fleet.sh stop + add).
set -uo pipefail
ROOT="${FLEET_ROOT:-$(git rev-parse --show-toplevel)}"; F="$ROOT/.fleet"; S="$F/state"
SOCK="${FLEET_SOCK:-fleet}"; HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
NUDGE="${FLEET_NUDGE:-150000}"; ALERT="${FLEET_ALERT:-185000}"; DEATHS="${FLEET_DEATHS:-3}"; WIN="${FLEET_DEATH_WIN:-60}"
DIALOG="${FLEET_DIALOG:-Do you want to|trust this folder|and don.t ask again|Esc to cancel}"
mkdir -p "$S"/launch "$S"/deaths "$S"/parked "$S"/marks
T() { tmux -L "$SOCK" "$@"; }
alert() { printf '%s %s %s\n' "$(date '+%F %T')" "$1" "$2" >> "$S/alerts.log"; echo "watch: $1 $2"; }
mark() { [[ ! -e $S/marks/$1.$2 ]] && touch "$S/marks/$1.$2"; }   # seat kind → true only the first time
unmark() { rm -f "$S/marks/$1.$2"; }

died() { # seat → 0 if it may relaunch; records the death, parks on a crash loop
  local f="$S/deaths/$1" now; now=$(date +%s)
  { awk -v c=$((now - WIN)) '$1 > c' "$f" 2>/dev/null; echo "$now"; } > "$f.tmp"; mv "$f.tmp" "$f"
  if (( $(wc -l < "$f") >= DEATHS )); then
    touch "$S/parked/$1"; : > "$f"
    alert "$1" "crash loop: $DEATHS deaths in ${WIN}s — parked, not relaunched (rm .fleet/state/parked/$1)"; return 1
  fi
}

relaunch() { # seat → fresh body; it boots from its handoff + card. Marks reset per life.
  local cmd; cmd="$("$HERE/fleet.sh" cmdline "$1")"
  rm -f "$S/marks/$1".* "$S/$1.json"
  if T list-windows -t fleet -F '#W' 2>/dev/null | grep -qx "$1"; then T respawn-pane -k -t "fleet:$1" -c "$ROOT" "$cmd"
  else T new-window -d -t fleet -n "$1" -c "$ROOT" "$cmd"; fi
  echo "watch: $1 relaunched"
}

ctx() { # seat → nudge once at NUDGE, alert once at ALERT
  local tok; tok=$(jq -r '.tok // 0 | floor' "$S/$1.json" 2>/dev/null) || return 0; [[ $tok =~ ^[0-9]+$ ]] || return 0
  if (( tok >= NUDGE )) && mark "$1" nudge; then
    "$HERE/fleet.sh" say "$1" "FLEET watch: context at ${tok} tokens. Finish the current step, commit by pathspec, write .fleet/handoff/$1.md (≤40 lines, newest first), then exit."
  fi
  (( tok >= ALERT )) && mark "$1" alert && alert "$1" "context ${tok} tokens, past the handoff nudge — fleet.sh peek $1"
  return 0
}

tick() {
  T has-session -t fleet 2>/dev/null || return 0
  local f s dead pane
  for f in "$S"/launch/*; do
    [[ -e $f ]] || continue; s=$(basename "$f")
    [[ -e $S/parked/$s ]] && continue
    dead=$(T list-panes -t "fleet:$s" -F '#{pane_dead}' 2>/dev/null | head -1)
    if [[ ${dead:-1} == 1 ]]; then died "$s" && relaunch "$s"; continue; fi
    pane="$(T capture-pane -p -t "fleet:$s" 2>/dev/null | grep -v '^[[:space:]]*$' | tail -n 15)"
    if grep -qE "$DIALOG" <<<"$pane"; then
      mark "$s" dialog && alert "$s" "stalled on a dialog — tmux -L $SOCK attach -t fleet:$s"
    else unmark "$s" dialog; fi
    ctx "$s"
  done
}

snap() { # item<TAB>value lines: newest alert, open gate rows, parked + live seats
  printf 'alert\t%s\n' "$(tail -n 1 "$S/alerts.log" 2>/dev/null | cut -c1-110)"
  printf 'gate\t%s\n' "$("$HERE/gate.sh" list open 2>/dev/null | grep -oE '^g[0-9a-f]+ \[[a-z]+' | tr -d '[' | xargs)"
  printf 'parked\t%s\n' "$(find "$S/parked" -type f -printf "%f\n" 2>/dev/null | sort | xargs)"
  printf 'seats\t%s\n' "$(T list-windows -t fleet -F '#W' 2>/dev/null | grep -vx watch | xargs)"
}
digest() {
  local now old k v o; now="$(snap)"; old="$(cat "$S/digest.last" 2>/dev/null)"
  [[ $now == "$old" ]] && return 0
  printf '%s\n' "$now" > "$S/digest.last"
  while IFS=$'\t' read -r k v; do
    o="$(awk -F'\t' -v k="$k" '$1 == k { print $2 }' <<<"$old")"
    [[ $v == "$o" ]] || echo "$(date +%H:%M) $k: ${v:-cleared}"
  done <<<"$now"
}

[[ ${BASH_SOURCE[0]} == "$0" ]] || return 0
case ${1:-loop} in
  once) tick ;;
  digest) digest ;;
  loop) while [[ ! -e $S/STOP ]]; do tick; sleep "${FLEET_TICK:-60}"; done; echo "watch: STOP present, exiting" ;;
  *) echo "usage: watch.sh [loop|once|digest]" >&2; exit 2 ;;
esac
