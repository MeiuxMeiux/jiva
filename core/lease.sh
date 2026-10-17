# shellcheck shell=bash
# lease — boss lease: never two, never zero (PLAN). Sourced (needs J, SOCK, T from lib.sh).
# $J/lease/boss = one line `<epoch> <session_id> <pane>`; pane is $TMUX_PANE when on our socket, else -.
# The boss statusline refreshes it each tick (refreshInterval keeps an idle boss ticking). A boss-named
# session that boots against a fresh lease (< TTL) from another session in another pane is refused:
# session-start says "lease held by <id>" and drops $J/lease/extra.<pane>; the watchdog kills that pane.
# Watchdog lease_tick: no boss window → spawn (never zero, unless parked or .jiva/profile = solo); live pane but lease > 3×TTL
# → flags/lease-stale + one toast; fresh again → flag cleared. JIVA_DRY=1 prints actions, no tmux/spawn.
LEASE="$J/lease/boss"; LEASE_TTL="${JIVA_LEASE_TTL:-90}"
declare -F hist >/dev/null || source "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")/history.sh"  # hist
LEASE_T0=$(date +%s); LEASE_GRACE="${JIVA_LEASE_GRACE:-30}"  # no spawn while `jiva up` is still launching

lease_pane() { # our pane id, only if we run inside this target's tmux socket (pane ids are per-server)
  [[ -n ${TMUX_PANE:-} && $(basename "${TMUX%%,*}") == "$SOCK" ]] && echo "$TMUX_PANE" || echo -
}
lease_read() { # → "age sid pane" or nothing
  local ts sid pane; [[ -s $LEASE ]] || return 1
  read -r ts sid pane < "$LEASE"; [[ $ts =~ ^[0-9]+$ ]] || return 1; echo "$(( $(date +%s) - ts )) $sid ${pane:--}"
}
lease_state() { # fresh|stale|none — stale = older than 3×TTL (boss hung or gone)
  local age _; read -r age _ < <(lease_read) || { echo none; return; }
  (( age > 3 * LEASE_TTL )) && echo stale || echo fresh
}
lease_held() { # sid pane → 0 (prints holder) if a fresh lease belongs to another session in another pane
  local age sid pane; read -r age sid pane < <(lease_read) || return 1
  (( age < LEASE_TTL )) && [[ $sid != "$1" ]] && [[ $pane == - || $pane != "$2" ]] && echo "$sid"
}
lease_take() { # sid pane → write the lease unless another fresh holder has it
  lease_held "$1" "$2" >/dev/null && return 1
  mkdir -p "$J/lease"; echo "$(date +%s) $1 $2" > "$LEASE.tmp" && mv "$LEASE.tmp" "$LEASE"
}
lease_act() { # tmux/jiva args… — the one door to side effects; JIVA_DRY=1 prints instead
  if [[ ${JIVA_DRY:-0} == 1 ]]; then echo "lease: would $*"; else "$@"; fi
}

lease_tick() { # watchdog: kill extras, heal zero, flag stale
  local panes lp st age _ e p
  panes="$(T list-panes -a -F '#{pane_id} #W #{pane_dead}' 2>/dev/null)"
  read -r age _ lp < <(lease_read) || lp=""
  st=$(lease_state)
  for e in "$J"/lease/extra.*; do        # never two: refused bosses, and stray panes in the boss window
    [[ -e $e ]] || continue; p=${e##*/extra.}; rm -f "$e"
    [[ $p != "$lp" ]] && grep -q "^$p " <<<"$panes" && lease_act T kill-pane -t "$p"
  done
  if [[ $st == fresh && -n $lp && $lp != - ]] && grep -q "^$lp boss 0" <<<"$panes"; then
    awk -v lp="$lp" '$2 == "boss" && $1 != lp { print $1 }' <<<"$panes" | while read -r p; do
      lease_act T kill-pane -t "$p"; done
  fi
  if ! grep -q ' boss 0$' <<<"$panes"; then  # never zero
    [[ -e $J/parked/boss || $(cat "$J/profile" 2>/dev/null) == solo ]] || (( $(date +%s) - LEASE_T0 < LEASE_GRACE )) || lease_act "$JV" spawn boss boss
    return
  fi
  if [[ $st == stale ]]; then
    mkdir -p "$J/flags"; [[ -e $J/flags/lease-stale ]] || { echo stale > "$J/flags/lease-stale"; hist lease st=stale age="$age"
      lease_act toast "boss lease stale (${age}s): boss hung? tmux -L $SOCK window boss"; }
  elif [[ -e $J/flags/lease-stale ]]; then rm -f "$J/flags/lease-stale"; hist lease st=fresh; fi
}
