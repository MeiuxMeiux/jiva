#!/usr/bin/env bash
# watchdog — non-LLM loop. Every 5s: merge `claude agents --json` + status-line state into
# .jiva/state.json (numbers/enums only), write the tmux bar, flag stuck sessions, nudge at 75% (150k;
# loop seat 100k) of the context ceiling, alert at 92.5% (breakers), respawn a session once it has written its handoff and gone idle, and run
# the breakers + dead-pane self-heal in core/breakers.sh, the boss lease (core/lease.sh), and the
# asks expiry + desk digest (core/asks.sh).
# Faults (notes/breakers.md): a failed state write → flags/disk-full once (no retry storm, cleared on the
# next good write); q5h/q7d ≥ JIVA_QUOTA_MAX (85) → flags/quota; status-right runs `status.sh bar` so a
# dead watchdog shows red. Sourcing this file (doctor-fault) defines tick without looping.
# `.jiva/STOP` stops it; `.jiva/paused` (core/governor.sh) skips heal, lease_tick and rotation respawns.
set -uo pipefail
# shellcheck source=core/lib.sh
source "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")/lib.sh"
JV="$JIVA_HOME/core/jiva.sh"; mkdir -p "$J"/{state,rotate,nudged}
CEIL="${JIVA_CEIL:-200000}"; NUDGE="${JIVA_NUDGE:-$((CEIL * 75 / 100))}"   # 150k: restart beats /clear (notes/fleet.md)
declare -A flagged=()

# shellcheck source=core/notify.sh
source "$JIVA_HOME/core/notify.sh"   # toast <text>: notify.log + desktop ping, never blocks
# shellcheck source=core/history.sh
source "$JIVA_HOME/core/history.sh"  # hist / hist_tok → history.jsonl (notes/history.md)
# shellcheck source=core/breakers.sh
source "$JIVA_HOME/core/breakers.sh"
# shellcheck source=core/lease.sh
source "$JIVA_HOME/core/lease.sh"
JIVA_NAME=watchdog   # board-log label for expired asks
# shellcheck source=core/asks.sh
source "$JIVA_HOME/core/asks.sh"
# shellcheck source=core/souls.sh
source "$JIVA_HOME/core/souls.sh"    # souls_bind / souls_map → sessions[].soul, bar chips, pane titles
# shellcheck source=core/governor.sh
source "$JIVA_HOME/core/governor.sh"  # paused, gov_tick (fleet $ cap), gov_handoff

wd_write() { # file content → atomic write; a failure (disk full) flags once instead of looping on errors
  if { printf '%s\n' "$2" > "$1.tmp" && mv "$1.tmp" "$1"; } 2>/dev/null; then
    [[ -e $J/flags/disk-full ]] && { rm -f "$J/flags/disk-full"; echo "watchdog: disk writable again"; }; return 0
  fi
  rm -f "$1.tmp"; [[ -e $J/flags/disk-full ]] && return 1
  flag disk-full disk-full 2>/dev/null || touch "$J/flags/disk-full"   # 0-byte flag still counts when full
  echo "watchdog: write to $1 failed (disk full?) — flagged disk-full"; toast "jiva: disk full, state not written"; return 1
}
wd_quota() { # merged-json → flags/quota "<5h>% 5h / <7d>% 7d" at ≥ JIVA_QUOTA_MAX; cleared below it
  local hi q5 q7; read -r hi q5 q7 < <(jq -r '[([.q5h // 0, .q7d // 0] | max | floor), .q5h // 0, .q7d // 0] | @tsv' <<<"$1")
  if (( hi >= ${JIVA_QUOTA_MAX:-85} )); then
    [[ -e $J/flags/quota ]] || { toast "jiva: quota at ${hi}% — spawn/assign refused"; hist quota st=pause q5h="$q5" q7d="$q7"; }
    flag quota "quota 5h ${q5}% 7d ${q7}%" 2>/dev/null
  elif [[ -e $J/flags/quota ]]; then rm -f "$J/flags/quota"; hist quota st=resume q5h="$q5" q7d="$q7"; fi
}
wd_bar() { # point status-right at `status.sh bar` (server() sets a plain cat; re-assert each tick)
  local want; want="#(JIVA_TARGET=$(printf %q "$TARGET") $(printf %q "$JIVA_HOME/core/status.sh") bar)"
  [[ $(T show -gv status-right 2>/dev/null) == "$want" ]] || T set -g status-right "$want" 2>/dev/null
  (( $(T show -gv status-right-length 2>/dev/null || echo 0) >= 200 )) || T set -g status-right-length 200 2>/dev/null   # soul chips
}
wd_title() { # window label → pane title (never rename windows: jiva.sh finds them by wN); Claude retitles, we re-assert
  [[ $(T display -p -t "jiva:$1" '#{pane_title}' 2>/dev/null) == "$2" ]] || T select-pane -t "jiva:$1" -T "$2" 2>/dev/null
}
wd_trust() { # windows whose pane sits at Claude's workspace-trust dialog (not in `claude agents` → "0 live")
  T list-windows -t jiva -F '#W' 2>/dev/null | while read -r n; do
    [[ $n == watchdog ]] || ! T capture-pane -p -t "jiva:$n" 2>/dev/null | grep -q 'trust this folder' || echo
  done | wc -l
}

tick() {
  local agents now merged ok=1 nf na nt
  ask_expire; ask_digest
  now=$(date +%s); nf=$(find "$J/flags" -type f | wc -l); na=$(ask_count); nt=$(wd_trust)
  agents="$(claude agents --json 2>/dev/null)" || { agents='[]'; ok=0; }
  merged="$(jq -c --arg root "$TARGET" --argjson now "$now" --argjson nf "$nf" --argjson na "$na" --argjson nt "$nt" --arg lease "$(lease_state)" --slurpfile st <(
      for f in "$J"/state/*.json; do [[ -e $f ]] && jq -c --arg n "$(basename "$f" .json)" '. + {name: $n}' "$f"; done
    ) '
    ($st | map({(.name): .}) | add // {}) as $s
    | [.[] | select(.cwd == $root and .name != null) | . as $a
       | {name, status, waiting: (.waitingFor // null),
          tok: ($s[.name].tok | numbers // 0 | floor), pct: ($s[.name].pct | numbers // 0), usd: ($s[.name].usd | numbers // 0),
          up: (($now * 1000 - (.startedAt | numbers // 0)) / 1000 | floor)}]
    | {ts: $now, lease: $lease, live: length, flags: ((map(select(.waiting != null)) | length) + $nf), asks: $na, trust: $nt,
       tok: (map(.tok) | add // 0), sessions: .,
       q5h: ([$st[].q5h | numbers] | max), q7d: ([$st[].q7d | numbers] | max)}' <<<"$agents")" || return
  local n all=() mine=()
  while IFS= read -r n; do [[ -n $n ]] || continue; all+=("$n"); [[ -e $J/launch/$n ]] && mine+=("$n"); done \
    < <(jq -r '.sessions[].name' <<<"$merged")
  souls_bind "${mine[@]}"   # only sessions jiva launched take a slot; bindings outlive respawn/up/down
  merged="$(jq -c --argjson sm "$(souls_map "${all[@]}")" '.sessions |= map(. + {soul: ($sm[.name] | {name, slot, color})})' \
    <<<"$merged")" || return
  wd_write "$J/state.json" "$merged"; wd_quota "$merged"; gov_tick "$merged"; wd_bar; hist_tok "$merged"
  local bar; bar="$(jq -r '"\(.live) live\(if .trust > 0 then " · \(.trust) at trust dialog" else "" end) · \(.flags) flag\(if .asks > 0 then " · asks \(.asks)" else "" end) · \(.tok / 1000 | floor)k\(if .q5h then " · 5h \(.q5h)%" else "" end)\([.sessions[] | select(.soul.slot != null)
    | "\(.soul.name)·\(.name) \(.tok / 1000 | floor)k"] | if length > 0 then " · " + join(" ") else "" end)"' <<<"$merged")"
  paused && bar="PAUSED · $bar"; declare -F stopped >/dev/null && stopped && bar="STOPPED · $bar"
  wd_write "$J/bar" "$bar"

  local name status waiting tok up usd label
  while IFS=$'\t' read -r name status waiting tok up usd label; do
    [[ -e $J/launch/$name ]] || continue            # only sessions jiva launched
    wd_title "$name" "$label"
    if [[ $waiting != null && -z ${flagged[$name]:-} ]]; then
      flagged[$name]=1; toast "$name is waiting: $waiting (tmux -L $SOCK window $name)"
    elif [[ $waiting == null ]]; then unset "flagged[$name]"; fi
    local nd=$NUDGE; [[ $(cat "$J/launch/$name") == loop ]] && nd=${JIVA_LOOP_NUDGE:-100000}   # loop restarts at 100k
    if (( tok >= nd )) && [[ ! -e $J/nudged/$name ]]; then
      touch "$J/nudged/$name"; hist nudge name="$name" tok="$tok"
      "$JV" say "$name" "JIVA watchdog: context at ${tok} tokens. Finish the current atom, run \`jiva handoff\`, then stop."
    fi
    breakers "$name" "$tok" "$up" "$usd"; gov_handoff "$name" "$tok"
    if [[ -e $J/rotate/$name && $status == idle ]] && ! parked "$name" && ! paused; then
      rm -f "$J/rotate/$name"; fresh_life "$name"; hist life name="$name" why=rotate tok="$tok"
      "$JV" respawn "$name" && "$JV" say "$name" "Continue from your handoff."
    fi
  done < <(jq -r '.sessions[] | [.name, .status, (.waiting // "null"), .tok, .up, .usd,
    (if .soul.slot != null then "\(.soul.name) · \(.name)" else .name end)] | @tsv' <<<"$merged")
  (( ok )) && ! paused && { heal "$(jq -r '.sessions[].name' <<<"$merged")"; lease_tick; }
}

[[ ${BASH_SOURCE[0]} == "$0" ]] || return 0
while [[ ! -e $J/STOP ]]; do tick; sleep "${JIVA_TICK:-5}"; done
echo "watchdog: STOP present, exiting"
