#!/usr/bin/env bash
# doctor-breakers — unit tests for the six breakers against a scratch .jiva in /tmp. Watchdog breakers
# (storm/ceiling/burn/time/usd) run core/breakers.sh with toast and `$JV say` stubbed to a log; repeat
# runs the real PostToolUse hook. Asserts flag file content. stop: .jiva/STOP vs every hook; scratch: `jiva scratch`; governor: pause/resume. Prints ok/FAIL; exit 1 on any FAIL.
set -uo pipefail
H="$(cd "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")/.." && pwd)"
S="$(mktemp -d /tmp/jiva-doctor-XXXXXX)"; trap 'rm -rf "$S"' EXIT
J="$S/.jiva"; mkdir -p "$J"; : > "$J/comb.log"
CEIL=200000; NUDGE=150000; JV=say_stub; bad=0
toast() { echo "toast $*" >> "$S/says"; }
say_stub() { echo "$*" >> "$S/says"; }
T() { return 1; }
JIVA_BURN=60000 JIVA_LIFE_MAX_MIN=90 JIVA_LIFE_MAX_USD=15
# shellcheck source=core/breakers.sh
source "$H/core/breakers.sh"
ok() { printf 'ok    breaker %s\n' "$1"; }
no() { printf 'FAIL  breaker %s\n' "$1"; bad=1; }
is() { # label name want — flag file content equals want ("" = no flag)
  local got; got="$(cat "$J/flags/$2" 2>/dev/null)"
  [[ $got == "$3" ]] && ok "$1" || no "$1: flag '${got}' want '$3'"
}
says() { grep -c "^say $1 " "$S/says" 2>/dev/null || echo 0; }

repeat() {
  local i rc in='{"session_id":"x","tool_name":"Bash","tool_input":{"command":"ls"}}'
  for i in 1 2 3 4; do
    CLAUDE_PROJECT_DIR="$S" JIVA_NAME=rp "$H/core/hooks/breaker.sh" <<<"$in" 2>/dev/null; rc=$?
  done
  (( rc == 2 )) || { no "repeat: 4th identical call exit $rc want 2"; return; }
  is "repeat (×4 identical → exit 2)" rp repeat
}

storm() { breakers st 175000 30 0; is "storm (≥nudge <180s)" st storm
  [[ -e $J/parked/st ]] || no "storm: not parked"; }

ceiling() { breakers ce 200000 600 0; breakers ce 201000 610 0; is "ceiling (≥ceil)" ce ceiling
  (( $(says ce) == 1 )) || no "ceiling: $(says ce) says want 1"; }

burnt() {
  echo "10:00 bu     claim core" >> "$J/comb.log"
  breakers bu 1000 600 0; is "burn baseline (no flag)" bu ""
  breakers bu 50000 610 0; [[ ! -e $J/flags/bu ]] || no "burn: flagged under threshold"
  breakers bu 62000 620 0; breakers bu 90000 630 0; is "burn (>60k since report)" bu burn
  (( $(says bu) == 1 )) || no "burn: $(says bu) says want 1"
  echo "10:05 bu     note: still on it" >> "$J/comb.log"
  breakers bu 91000 640 0; is "burn clears on new comb line" bu ""
}

life_time() { breakers ti 1000 $((90 * 60)) 0; is "time at cap (no flag)" ti ""
  breakers ti 1000 $((90 * 60 + 1)) 0; breakers ti 1000 6000 0; is "time (>90 min)" ti time
  (( $(says ti) == 1 )) || no "time: $(says ti) says want 1"
  fresh_life ti; rm -f "$J/flags/ti"; breakers ti 1000 6000 0
  (( $(says ti) == 2 )) || no "time: fresh_life did not re-arm the say"; }

life_usd() { breakers us 1000 600 14.99; is "usd under cap (no flag)" us ""
  breakers us 1000 610 15.2; breakers us 1000 620 16; is "usd (>\$15)" us usd
  (( $(says us) == 1 )) || no "usd: $(says us) says want 1"; }

: > "$S/says"
heal_storm() { # counters only: 3 heals allowed, the 4th parks + flags once; old heals age out
  local i; for i in 1 2 3; do heal_ok hs || no "heal-storm: heal $i refused"; done
  heal_ok hs && no "heal-storm: 4th heal allowed"; is "heal-storm (≥3 heals in 5 min)" hs heal-storm
  [[ -e $J/parked/hs ]] || no "heal-storm: not parked"
  (( $(grep -c 'toast hs parked: heal storm' "$S/says") == 1 )) || no "heal-storm: toast count != 1"
  printf '%s\n' $(( $(date +%s) - 400 )){,,} > "$J/heals/ho"
  heal_ok ho && ok "heal-storm: heals older than 5 min age out" || no "heal-storm: stale heals counted"; }

stop() { # .jiva/STOP in a scratch target: each hook's observable effect, then STOP removed → normal again
  local h="$H/core/hooks" e=(env CLAUDE_PROJECT_DIR="$S" JIVA_NAME=sp JIVA_ROLE=worker) out
  local ed='{"session_id":"s","tool_name":"Edit","tool_input":{"file_path":"'"$S"'/a/b/c.txt"}}'
  touch "$J/STOP"; rm -f "$J/affinity.tsv" "$J/state/sp.calls"
  out="$("${e[@]}" "$h/guard.sh" <<<'{"tool_name":"Read","tool_input":{}}')"
  [[ $(jq -r '.hookSpecificOutput | .permissionDecision + "/" + .permissionDecisionReason' <<<"$out") == "deny/JIVA STOPPED" ]] &&
    ok "stop: guard denies any tool (JIVA STOPPED)" || no "stop: guard out '$out'"
  out="$("${e[@]}" "$h/session-start.sh" </dev/null | jq -r .hookSpecificOutput.additionalContext)"
  [[ $out == "STOPPED: .jiva/STOP present, do nothing, wait" ]] && ok "stop: session-start one STOPPED line" || no "stop: session-start '$out'"
  out="$("${e[@]}" "$h/statusline.sh" <<<'{"session_id":"s"}')"
  [[ $out == "STOPPED · "* ]] && ok "stop: statusline prefixed STOPPED" || no "stop: statusline '$out'"
  local i; for i in 1 2 3 4; do "${e[@]}" "$h/breaker.sh" <<<"$ed" 2>/dev/null || no "stop: breaker exit $? under STOP"; done
  [[ ! -e $J/state/sp.calls && ! -e $J/flags/sp ]] && ok "stop: breaker writes no ring/flag" || no "stop: breaker wrote"
  "${e[@]}" "$h/affinity.sh" <<<"$ed"; [[ ! -e $J/affinity.tsv ]] && ok "stop: affinity writes nothing" || no "stop: affinity wrote"
  rm -f "$J/STOP"; "${e[@]}" "$h/affinity.sh" <<<"$ed"
  out="$("${e[@]}" "$h/guard.sh" <<<'{"tool_name":"Read","tool_input":{}}')"
  [[ -s $J/affinity.tsv && -z $out ]] && ok "stop: removed → hooks act again" || no "stop: no recovery after rm STOP"
}

scratch() { # jiva scratch: literal root, prints path, rm only under the root, refuses odd names/escapes
  local sc="$H/core/scratch.sh" n="doctor-$$" d
  d="$("$sc" "$n")"; [[ $d == /tmp/jiva-scratch/$n && -d $d ]] && ok "scratch: makes + prints $d" || no "scratch: got '$d'"
  "$sc" ../etc >/dev/null 2>&1 && no "scratch: accepted ../etc" || ok "scratch: refuses ../ names"
  ln -s "$S" "$d/x" && "$sc" "$n/x" rm >/dev/null 2>&1 && no "scratch: accepted a / in name" || ok "scratch: refuses nested names"
  ln -sfn "$S" "/tmp/jiva-scratch/$n-l"; "$sc" "$n-l" rm >/dev/null 2>&1 && no "scratch: rm followed a symlink out" || ok "scratch: rm refuses symlink escape"
  [[ -d $S/.jiva ]] || no "scratch: symlink target damaged"; unlink "/tmp/jiva-scratch/$n-l"
  "$sc" "$n" rm >/dev/null && [[ ! -e $d ]] && ok "scratch: rm cleans the subpath" || no "scratch: rm left $d"
}

guardrules() { # git stash list|show pass, bare stash denied; packs/local/ (the keeper's roster) denied for Write/Bash
  local g="$H/core/hooks/guard.sh" c
  gd() { CLAUDE_PROJECT_DIR="$S" "$g" <<<"$(jq -nc --arg t "$1" --arg k "$2" --arg v "$3" '{tool_name: $t, tool_input: {($k): $v}}')" 2>/dev/null; }
  for c in "git stash list" "git -C x stash show -p"; do gd Bash command "$c" && ok "guard: '$c' passes" || no "guard: '$c' denied"; done
  for c in "git stash" "git stash pop"; do gd Bash command "$c" && no "guard: '$c' passed" || ok "guard: '$c' denied"; done
  gd Write file_path "$S/packs/local/a.yaml" && no "guard: Write packs/local passed" || ok "guard: Write under packs/local denied"
  gd Bash command "rm -f packs/local/x.webp" && no "guard: Bash packs/local passed" || ok "guard: Bash touching packs/local denied"
  gd Bash command "echo hi > packs/local/a" && no "guard: > into packs/local passed" || ok "guard: redirect into packs/local denied"
  gd Bash command "echo 'RULE: packs/local/ is keeper' >> .jiva/tasks/w2.md" && ok "guard: rule quoted into a card passes" || no "guard: mention denied (false positive)"
  gd Bash command $'cat > c.md <<\'EOF\'\nnever write under packs/local/\nEOF' && ok "guard: heredoc mention passes" || no "guard: heredoc mention denied"
  gd Bash command "cat packs/local/r.yaml" && ok "guard: read of packs/local passes" || no "guard: read denied"
  gd Edit file_path "$S/packs/default/a.yaml" && ok "guard: packs/default still editable" || no "guard: packs/default denied"
}

governor() { # jiva pause/resume against the scratch TARGET only (never the live hive)
  local jv=(env -u JIVA_PANE_TARGET JIVA_TARGET="$S" "$H/bin/jiva")
  (cd "$S" && "${jv[@]}" pause x >/dev/null); [[ $(cut -d' ' -f2- "$J/paused" 2>/dev/null) == x ]] &&
    ok "governor: jiva pause x writes .jiva/paused" || no "governor: no scratch .jiva/paused after pause"
  (cd "$S" && "${jv[@]}" resume >/dev/null); [[ ! -e $J/paused ]] && ok "governor: jiva resume removes it" || no "governor: paused left after resume"
}

repeat; storm; heal_storm; ceiling; burnt; life_time; life_usd; stop; scratch; guardrules; governor
exit $bad
