#!/usr/bin/env bash
# doctor-souls — core/souls.sh against a scratch J (/tmp/jiva-doctor-*) and a stub 24-slot pack (no repo art):
# bind is stable across calls, takes the lowest free slot, a 13th session gets none (label = session name),
# boss → slot 0, souls.json survives a fake `jiva up` (fresh shell, state/launch wiped, reverse bind order),
# and one watchdog tick (stub claude, no tmux) writes sessions[].soul + bar chips. Prints ok/FAIL; exit 1 on FAIL.
set -uo pipefail
H="$(cd "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")/.." && pwd)"
S="$(mktemp -d /tmp/jiva-doctor-XXXXXX)"; trap 'rm -rf "$S"' EXIT
export JIVA_TARGET="$S" JIVA_SOUL_PACK="$S/pack.json"
bad=0
ok() { printf 'ok    souls %s\n' "$1"; }
no() { printf 'FAIL  souls %s\n' "$1"; bad=1; }
eq() { if [[ $2 == "$3" ]]; then ok "$1"; else no "$1 (got '$2', want '$3')"; fi; }
sh() { ( source "$H/core/lib.sh"; source "$H/core/souls.sh"; "$@" ) 2>&1; }   # fresh shell per call, like a respawn

jq -n '{name: "stub", boss: {slot: 0, name: "Chief", color: "#ffffff"},
  slots: [range(1; 25) | {slot: ., name: "S\(.)", color: "#0000\(. + 10)", avatar: "avatars/\(.).svg"}]}' > "$S/pack.json"
mkdir -p "$S/.jiva"

eq "first bind → slot 1" "$(sh soul_bind w4)" 1
eq "bind is stable across calls" "$(sh soul_bind w4; sh soul_bind w4)" $'1\n1'
eq "boss → slot 0, not stored" "$(sh soul_bind boss) $(jq -r 'has("boss")' "$S/.jiva/souls.json")" "0 false"
eq "desk/watchdog never bound" "$(sh souls_bind desk watchdog; jq -c 'keys' "$S/.jiva/souls.json")" '["w4"]'
jq -c '. + {w1: {slot: 2}, w9: {slot: 4}}' "$S/.jiva/souls.json" > "$S/s" && mv "$S/s" "$S/.jiva/souls.json"
eq "lowest free slot (1,2,4 taken → 3)" "$(sh soul_bind w7)" 3
eq "batch bind fills 5.. in natural order" "$(sh souls_bind w10 w2; jq -r '"\(.w2.slot) \(.w10.slot)"' "$S/.jiva/souls.json")" "5 6"
sh souls_bind w11 w12 w13 w14 w15 w16 >/dev/null
eq "12 live slots used" "$(jq '[.[].slot] | sort | . == [range(1; 13)]' "$S/.jiva/souls.json")" true
eq "13th session → no slot" "$(sh soul_bind w17; echo "rc=$?")" "rc=1"
eq "unbound label = session name" "$(sh soul_label w17)|$(sh soul_of w17)" $'w17|w17\t\t\t'
eq "soul_of = pack name/slot/color/avatar" "$(sh soul_of w7)" $'S3\t3\t#000013\tavatars/3.svg'
eq "soul_label" "$(sh soul_label w4) / $(sh soul_label boss)" "S1 · w4 / Chief · boss"
before="$(jq -cS . "$S/.jiva/souls.json")"
mkdir -p "$S/.jiva/state" "$S/.jiva/launch"; rm -f "$S/.jiva/state/"*.json "$S/.jiva/launch/"*   # fake `jiva up` / respawn
sh souls_bind w16 w15 w14 w13 w12 w11 w10 w9 w7 w4 w2 w1 >/dev/null
eq "souls.json survives a fake up (reverse bind order)" "$(jq -cS . "$S/.jiva/souls.json")" "$before"
printf 'garbage' > "$S/.jiva/souls.json"
eq "corrupt souls.json → rebuilt, w3 → slot 1" "$(sh soul_bind w3)" 1

# one watchdog tick: stub claude lists boss + w1 + a foreign session; only launched ones bind
rm -f "$S/.jiva/souls.json"; mkdir -p "$S/stub"
cat > "$S/stub/claude" <<'SH'
#!/usr/bin/env bash
[[ ${1:-} == agents ]] && jq -nc --arg c "$JIVA_TARGET" '[{name: "boss"}, {name: "w1"}, {name: "jiva-12"}]
  | map(. + {cwd: $c, status: "idle", startedAt: (now * 1000)})'
SH
printf '#!/bin/sh\nexit 1\n' > "$S/stub/tmux"; chmod +x "$S/stub/claude" "$S/stub/tmux"
echo boss > "$S/.jiva/launch/boss"; echo worker > "$S/.jiva/launch/w1"
( export PATH="$S/stub:$PATH" JIVA_DRY=1; source "$H/core/watchdog.sh"; toast() { :; }; breakers() { :; }; heal() { :; }
  lease_tick() { :; }; tick ) >/dev/null 2>&1
eq "state.json: w1 soul" "$(jq -c '.sessions[] | select(.name == "w1") | .soul' "$S/.jiva/state.json")" '{"name":"S1","slot":1,"color":"#000011"}'
eq "state.json: boss soul slot 0" "$(jq -r '.sessions[] | select(.name == "boss") | .soul.slot' "$S/.jiva/state.json")" 0
eq "state.json: foreign session unbound" "$(jq -c '.sessions[] | select(.name == "jiva-12") | .soul' "$S/.jiva/state.json")" \
  '{"name":"jiva-12","slot":null,"color":null}'
[[ $(cat "$S/.jiva/bar") == *"Chief·boss 0k S1·w1 0k" ]] && ok "bar chips 'S1·w1 0k'" || no "bar: $(cat "$S/.jiva/bar")"
exit $bad
