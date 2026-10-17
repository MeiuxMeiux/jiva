# shellcheck shell=bash
# souls — semi-persistent slot binding (notes/roster.md). Sourced after lib.sh ($J, $JIVA_HOME).
# $J/souls.json = {"w1": {"slot": 1}, …}: a session keeps its slot across respawn/rotate/up/down; a new
# session takes the lowest free live slot (1–$SOUL_MAX); none free → unbound (label = session name).
# boss → slot 0 (pack .boss), never stored; desk/watchdog are not bodies → never bound.
# Names are LABELS only (dash, bar, pane titles): never injected into prompts or role payloads (PLAN "Souls").
# Addresses, claims and messaging stay wN. Writes are flock'd ($J/souls.lock) and atomic (tmp → mv).
SOUL_PACK="${JIVA_SOUL_PACK:-$JIVA_HOME/packs/default/pack.json}"; SOUL_MAX="${JIVA_SOUL_MAX:-12}"

souls_bind() { # session… → bind every unbound one (skips boss/desk/watchdog); prints nothing
  local want; want="$(printf '%s\n' "$@" | grep -vxE 'boss|desk|watchdog|' | sort -V | jq -Rsc 'split("\n") | map(select(. != ""))')"
  [[ $want == '[]' ]] && return 0
  mkdir -p "$J"
  (
    flock -w 5 9 || exit 1
    local cur; cur="$(jq -c 'if type == "object" then . else {} end' "$J/souls.json" 2>/dev/null)" || cur='{}'
    [[ -n $cur ]] || cur='{}'
    jq -c --argjson want "$want" --argjson max "$SOUL_MAX" 'reduce $want[] as $n (.;
        if .[$n].slot then . else
          (([range(1; $max + 1)] - [.[].slot]) | first) as $s | if $s then .[$n] = {slot: $s} else . end end)' \
      <<<"$cur" > "$J/souls.json.tmp" && mv "$J/souls.json.tmp" "$J/souls.json"
  ) 9>"$J/souls.lock"
}

soul_bind() { # session → its slot (binding it if new); boss → 0; exit 1 + empty when unbound
  [[ $1 == boss ]] && { echo 0; return 0; }
  souls_bind "$1"
  local s; s="$(jq -r --arg n "$1" '.[$n].slot // empty' "$J/souls.json" 2>/dev/null)"
  [[ -n $s ]] && echo "$s"
}

souls_map() { # session… → {"<s>": {name, slot, color, avatar}} from souls.json + pack (no binding); unbound → label = s
  printf '%s\n' "$@" | jq -Rsc --slurpfile p "$SOUL_PACK" --slurpfile b <(cat "$J/souls.json" 2>/dev/null || echo '{}') '
    ($p[0]) as $p | ($b[0] // {}) as $b
    | split("\n") | map(select(. != "")) | map({(.): (
        if . == "boss" then ($p.boss + {avatar: ($p.boss.avatar // null)})
        else (($b[.].slot // null) as $s | ($p.slots | map(select(.slot == $s)) | first)
              // {name: ., slot: null, color: null, avatar: null}) end
        | {name, slot, color, avatar})}) | add // {}'
}

soul_of() { # session → "name\tslot\tcolor\tavatar" (unbound: session name and empty fields)
  souls_map "$1" | jq -r --arg n "$1" '.[$n] | [.name, .slot // "", .color // "", .avatar // ""] | @tsv'
}

soul_label() { # session [sep] → "Ash · w1" (sep default " · "); unbound → session name
  local n; n="$(souls_map "$1" | jq -r --arg n "$1" 'if .[$n].slot != null then .[$n].name else "" end')"
  if [[ -n $n ]]; then printf '%s%s%s\n' "$n" "${2- · }" "$1"; else printf '%s\n' "$1"; fi
}
