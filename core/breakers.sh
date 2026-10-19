# shellcheck shell=bash
# breakers — sourced by watchdog.sh (needs J, JV, CEIL, NUDGE, T, toast). A flag is
# .jiva/flags/<name> holding a one-word reason; state.json `flags` counts them. One-shot says are
# marked in .jiva/nudged/<name>.<kind> and cleared per life by fresh_life. A parked session
# (.jiva/parked/<name>) is never respawned — the desk unparks it with rm.
mkdir -p "$J"/{flags,parked,nudged,heals}
declare -F hist >/dev/null || source "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")/history.sh"  # hist (notes/history.md)
declare -A missing=()
HEAL_MAX="${JIVA_HEAL_MAX:-3}"; HEAL_WIN="${JIVA_HEAL_WIN:-300}"
BURN="${JIVA_BURN:-60000}"; LIFE_MIN="${JIVA_LIFE_MAX_MIN:-90}"; LIFE_USD="${JIVA_LIFE_MAX_USD:-15}"

flag() { # name reason → flags/<name>; a new first word of the reason → one `trip` history line (quota has its own)
  local old; old="$(cat "$J/flags/$1" 2>/dev/null)"; printf '%s\n' "$2" > "$J/flags/$1" || return
  [[ $1 == quota || ${old%% *} == "${2%% *}" ]] || hist trip name="$1" trip="${2%% *}"
}
parked() { [[ -e $J/parked/$1 ]]; }
once() { [[ ! -e $J/nudged/$1.$2 ]] && touch "$J/nudged/$1.$2"; }  # name kind → true the first time
fresh_life() { rm -f "$J/nudged/$1" "$J/nudged/$1".{ceil,alert,burn,time,usd,last,pause}; }

burn() { # name tok — tokens since this session's last comb line; nudged/<name>.last = "lines tok"
  local name=$1 tok=$2 n lc=-1 lt=0
  n=$(awk -v n="$name" '$2 == n' "$J/comb.log" 2>/dev/null | wc -l)
  [[ -e $J/nudged/$name.last ]] && read -r lc lt < "$J/nudged/$name.last"
  [[ $lc =~ ^-?[0-9]+$ && $lt =~ ^-?[0-9]+$ ]] || { lc=-1; lt=0; }   # file text never reaches (( ))
  if (( n != lc )); then
    echo "$n $tok" > "$J/nudged/$name.last"; rm -f "$J/nudged/$name.burn"
    [[ $(cat "$J/flags/$name" 2>/dev/null) == burn ]] && rm -f "$J/flags/$name"
  elif (( tok - lt > BURN )) && once "$name" burn; then
    flag "$name" burn
    "$JV" say "$name" "JIVA: $(( (tok - lt) / 1000 ))k tokens since your last report — \`jiva report note\` what you're doing or \`jiva report blocked\`."
  fi
}

auth() { # name → flags/<name>-auth + one toast when the pane tail shows a usage-limit / login / API error
  local f="$J/flags/$1-auth" hit
  hit="$(T capture-pane -p -t "jiva:$1" 2>/dev/null | grep -v '^[[:space:]]*$' | tail -n "${JIVA_AUTH_TAIL:-8}" |
    grep -iEo 'limit reached|run /login|API Error: ?[0-9]+' | head -1)"
  if [[ -n $hit ]]; then [[ -e $f ]] || { flag "$1-auth" "auth $hit"; toast "$1: \"$hit\" in its pane — log in / wait for the limit"; }
  else rm -f "$f"; fi
}

breakers() { # name tok up [usd]
  local name=$1 tok=$2 up=$3 usd=${4:-0}
  if (( tok >= NUDGE && up < 180 )) && ! parked "$name"; then   # rotation storm
    flag "$name" storm; touch "$J/parked/$name"; hist park name="$name" why=storm tok="$tok"
    toast "$name parked: rotation storm (${tok} tok ${up}s after boot). rm .jiva/parked/$name to unpark"
  fi
  if (( tok >= ${JIVA_ALERT:-$((CEIL * 925 / 1000))} )) && once "$name" alert; then   # 185k: alert the desk (notify.log)
    toast "$name at ${tok} tokens, past the handoff nudge — check it: just peek $name"
  fi
  if (( tok >= CEIL )) && [[ ! -e $J/nudged/$name.ceil ]]; then  # hard ceiling: one say
    touch "$J/nudged/$name.ceil"; flag "$name" ceiling
    "$JV" say "$name" "JIVA watchdog: hard ceiling at ${tok} tokens. Stop now: run \`jiva handoff\` and end your turn."
  fi
  burn "$name" "$tok"
  auth "$name"
  if (( up > LIFE_MIN * 60 )) && once "$name" time; then        # per-life time ceiling
    flag "$name" time
    "$JV" say "$name" "JIVA watchdog: this life is $(( up / 60 )) min old (cap ${LIFE_MIN}). Run \`jiva handoff\` and end your turn."
  fi
  if awk -v u="$usd" -v m="$LIFE_USD" 'BEGIN { exit !(u > m) }' && once "$name" usd; then  # per-life $
    flag "$name" usd
    "$JV" say "$name" "JIVA watchdog: this life cost \$${usd%.*} (cap \$${LIFE_USD}). Run \`jiva handoff\` and end your turn."
  fi
}

heal_ok() { # name → 0 and record a heal; ≥HEAL_MAX heals in HEAL_WIN s → park + flag heal-storm, 1
  local n=$1 now f; now=$(date +%s); f="$J/heals/$n"
  awk -v c=$((now - HEAL_WIN)) '$1 > c' "$f" 2>/dev/null > "$f.tmp"; mv "$f.tmp" "$f"
  if (( $(wc -l < "$f") >= HEAL_MAX )); then
    flag "$n" heal-storm; touch "$J/parked/$n"; : > "$f"; hist park name="$n" why=heal-storm   # unpark (rm) starts a fresh count
    toast "$n parked: heal storm (${HEAL_MAX} respawns in ${HEAL_WIN}s). rm .jiva/parked/$n to unpark"; return 1
  fi
  echo "$now" >> "$f"
}

heal() { # live-names → respawn a launched session whose pane died or whose agent is gone >15s
  local live=$1 now panes f n; now=$(date +%s)
  panes="$(T list-panes -s -t jiva -F '#W #{pane_dead}' 2>/dev/null)" || return
  for f in "$J"/launch/*; do
    [[ -e $f ]] || continue; n=$(basename "$f")
    if grep -qx "$n" <<<"$live" && ! grep -qx "$n 1" <<<"$panes"; then unset "missing[$n]"; continue; fi
    parked "$n" && continue
    T capture-pane -p -t "jiva:$n" 2>/dev/null | grep -q 'trust this folder' && continue  # keeper's click
    : "${missing[$n]:=$now}"
    grep -qx "$n 1" <<<"$panes" || (( now - missing[$n] > 15 )) || continue
    missing[$n]=$now; heal_ok "$n" || continue
    echo "watchdog: $n dead or missing, respawning"; hist heal name="$n"; hist life name="$n" why=heal
    fresh_life "$n"
    "$JV" spawn "$(cat "$f")" "$n" && "$JV" say "$n" "Continue from your handoff."
  done
}
