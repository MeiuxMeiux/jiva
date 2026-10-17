#!/usr/bin/env bash
# profile — fleet sizing for `jiva up [profile]` (notes/fleet.md). Prints line 1 "<boss> <loop> <workers> <name>",
# then one "profile: … because …" line per reason. jiva.sh up reads line 1; the rest is shown to the human.
#   solo        watchdog + 1 worker, no boss seat — the desk acts as boss (lease never spawns one)
#   duo[:N]     boss + N workers (N default 2) — the classic default; a bare number N means duo:N
#   full[:N]    boss + loop + N workers — loop is opt-in, for repos with live prod (core/roles/loop.md)
#   (empty)     auto: solo when the host or the quota is tight, else duo; full is never auto-picked
# Knobs: JIVA_SEAT_MB (700) per seat · JIVA_WORKERS (2) auto worker count · JIVA_SOLO_QUOTA (70) % that forces solo.
set -uo pipefail
# shellcheck source=core/lib.sh
source "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")/lib.sh"
arg=${1:-}; name=${arg%%:*}; n=${arg#*:}; [[ $arg == *:* ]] || n=""
[[ $name =~ ^[0-9]+$ ]] && { n=$name; name=duo; }
[[ -z $n || $n =~ ^[0-9]+$ ]] || { echo "profile: bad worker count '$n'" >&2; exit 2; }

cpus=$(nproc 2>/dev/null || echo 1)
mem=$(free -m 2>/dev/null | awk '/^Mem:/ { print $7 }'); mem=${mem:-0}
seat=${JIVA_SEAT_MB:-700}; fit=$(( (mem - 1024) / seat )); (( fit < 0 )) && fit=0
q="$( { cat "$J"/state/*.json 2>/dev/null || true; } | jq -s '[.[] | .q7d, .q5h | numbers] | max // 0 | floor')"
gov=running; [[ -e $J/paused ]] && gov=paused
miss=""; for t in nproc free; do command -v "$t" >/dev/null || miss+=" $t"; done
why=("host: ${cpus} cpu, ${mem} MB available → room for ${fit} seats at ${seat} MB" "quota: max(5h,7d) ${q}% · governor ${gov}")
[[ -z $miss ]] || why+=("host:${miss} not found (macOS?) — host size unknown, so auto picks solo; ask for duo:N or full:N yourself")

if [[ -z $name ]]; then
  w=${JIVA_WORKERS:-2}
  if (( q >= ${JIVA_SOLO_QUOTA:-70} )); then name=solo; why+=("auto → solo because quota ${q}% ≥ ${JIVA_SOLO_QUOTA:-70}% (one body burns least)")
  elif (( fit < 3 || cpus < 2 )); then name=solo; why+=("auto → solo because the host fits < 3 seats")
  else
    (( fit - 1 < w )) && w=$(( fit - 1 ))
    name=duo; n=$w; why+=("auto → duo:$w because host and quota allow boss + $w (full/loop is opt-in: \`jiva up full\`)")
  fi
else why+=("asked for $name${n:+:$n}"); fi

case $name in
  solo) [[ -z $n || $n == 1 ]] || { echo "profile: solo is exactly 1 worker" >&2; exit 2; }; plan="0 0 1 solo"
        why+=("solo: no boss seat — the desk plans and writes cards (core/roles/desk.md)") ;;
  duo)  plan="1 0 ${n:-2} duo" ;;
  full) plan="1 1 ${n:-2} full"; why+=("full: loop seat needs .jiva/loop.cmd (one feed line, e.g. journalctl -f -p err)") ;;
  *) echo "profile: unknown '$name' (solo | duo[:N] | full[:N] | N)" >&2; exit 2 ;;
esac
read -r _ _ nw _ <<<"$plan"; (( nw > 4 )) && why+=("note: the boss steers ≤4 workers well; above that split into lanes")
[[ $gov == paused ]] && why+=("governor paused: seats start, but heal/lease spawn/rotation stay off (jiva resume)")
echo "$plan"; printf 'profile: %s\n' "${why[@]}"
