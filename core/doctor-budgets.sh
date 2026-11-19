#!/usr/bin/env bash
# doctor-budgets — the rest of docs/history/PLAN.md's "budgets are tests", plus caps, governor and the Stop-hook rule:
#   CLAUDE.md ≤8 rule lines (headings/blank not counted) · worker caps: 6 ok, 7 needs JIVA_CONFIRM=1, 13 refused
#   context nudge (150k = 75% of the 200k ceiling): watchdog tick (scratch J, stubbed say) nudges once per life, again after fresh_life
#   state.json diet: numbers/enums + names only — no string >40 chars or multi-line (scratch tick + live file)
#   claude --version ≥ 2.1.236; WARN spike-stale when it ≠ .jiva/spike.version (written by a green `jiva spike`)
#   no Stop/SubagentStop hook in JIVA's settings/plugin (a keep-going loop engine); WARN if user/project has one
# ok/WARN/FAIL lines; exit 1 on any FAIL (WARN never fails).
set -uo pipefail
H="$(cd "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")/.." && pwd)"
# shellcheck source=core/lib.sh
source "$H/core/lib.sh"
FLOOR=2.1.236; bad=0
ok() { printf 'ok    budget %s\n' "$1"; }
no() { printf 'FAIL  budget %s\n' "$1"; bad=1; }
warn() { printf 'WARN  budget %s\n' "$1"; }

claudemd() { # rule lines only: a heading or blank line is not a rule
  local f="$TARGET/CLAUDE.md" n
  [[ -f $f ]] || { ok "CLAUDE.md absent (skipped)"; return; }
  n=$(grep -cvE '^[[:space:]]*(#|$)' "$f")
  (( n <= 8 )) && ok "CLAUDE.md $n rule lines (≤8)" || no "CLAUDE.md $n rule lines (>8) — boot reads it every life"
}

caps() { # cap_ok lifted out of jiva.sh so no tmux/spawn is needed
  eval "$(sed -n '/^cap_ok() {/,/^}/p' "$H/core/jiva.sh")"
  declare -F cap_ok >/dev/null || { no "caps: cap_ok missing from core/jiva.sh"; return; }
  local r=""
  JIVA_CONFIRM='' cap_ok 6 2>/dev/null && r+=y || r+=n
  JIVA_CONFIRM='' cap_ok 7 2>/dev/null && r+=y || r+=n
  JIVA_CONFIRM=1 cap_ok 7 2>/dev/null && r+=y || r+=n
  JIVA_CONFIRM=1 cap_ok 12 2>/dev/null && r+=y || r+=n
  JIVA_CONFIRM=1 cap_ok 13 2>/dev/null && r+=y || r+=n
  [[ $r == ynyyn ]] && ok "caps: 6 ok · 7 needs JIVA_CONFIRM=1 · 12 ok confirmed · 13 refused" ||
    no "caps: got $r for 6/7/7c/12c/13c (want ynyyn)"
}

diet() { # file label → strings must be names/enums (≤40 chars, one line)
  local f=$1 x
  [[ -s $f ]] || { ok "state diet $2: no file (skipped)"; return; }
  x="$(jq -r '[.. | strings | select(length > 40 or test("\n"))] | first // empty' "$f" 2>/dev/null)" ||
    { no "state diet $2: not JSON"; return; }
  [[ -z $x ]] && ok "state diet $2: numbers/enums + names only" || no "state diet $2: free text '${x:0:60}'"
}

nudge() { # scratch watchdog tick: tok over NUDGE → one say per life; fresh_life re-arms it
  local S; S="$(mktemp -d /tmp/jiva-doctor-XXXXXX)"
  mkdir -p "$S/stub" "$S/.jiva"/{state,launch}
  printf '#!/usr/bin/env bash\n[[ ${1:-} == agents ]] && jq -nc --arg c "$JIVA_TARGET" %s\n' \
    "'[{name: \"w1\", cwd: \$c, status: \"busy\", startedAt: ((now - 60) * 1000)}]'" > "$S/stub/claude"
  chmod +x "$S/stub/claude"
  ( export JIVA_TARGET="$S" JIVA_HOOKS=settings JIVA_DRY=1 JIVA_SAY=true JIVA_NOTIFY=off PATH="$S/stub:$PATH"
    source "$H/core/watchdog.sh"; toast() { :; }; T() { :; }
    jv() { [[ $1 == say ]] && echo "$2|$3" >> "$S/says"; return 0; }; JV=jv
    CEIL=1000; NUDGE=$((CEIL * 75 / 100)); echo worker > "$J/launch/w1"
    echo '{"tok":900,"pct":90}' > "$J/state/w1.json"
    tick; tick; c1=$(grep -c 'context at' "$S/says" 2>/dev/null)
    fresh_life w1; tick; c2=$(grep -c 'context at' "$S/says" 2>/dev/null)
    echo '{"tok":700,"pct":70}' > "$J/state/w1.json"; fresh_life w1; tick; c3=$(grep -c 'context at' "$S/says" 2>/dev/null)
    echo "${c1:-0} ${c2:-0} ${c3:-0}" > "$S/counts" ) >/dev/null 2>&1
  read -r c1 c2 c3 < "$S/counts" 2>/dev/null
  [[ "${c1:-}/${c2:-}/${c3:-}" == 1/2/2 ]] && ok "context nudge: once per life, re-armed by fresh_life, silent under 75%" ||
    no "context nudge: says per phase ${c1:-?}/${c2:-?}/${c3:-?} (want 1/2/2)"
  diet "$S/.jiva/state.json" "(scratch tick)"
  echo '{"ts":1,"sessions":[{"name":"w1","waiting":"Allow Bash to run a long free-text command here?"}]}' > "$S/bad"
  [[ $(diet "$S/bad" x) == FAIL* ]] && ok "state diet catches free text" || no "state diet passed free text"
  rm -rf "$S"
}

version() { # floor + spike freshness
  local v s
  v="$(claude --version 2>/dev/null | grep -oE '^[0-9]+(\.[0-9]+)+')" || v=""
  [[ -n $v ]] || { warn "claude --version unreadable (claude not on PATH?)"; return; }
  [[ $(printf '%s\n%s\n' "$FLOOR" "$v" | sort -V | head -1) == "$FLOOR" ]] &&
    ok "claude $v ≥ $FLOOR" || no "claude $v < floor $FLOOR"
  s="$(cat "$J/spike.version" 2>/dev/null)"
  if [[ -z $s ]]; then warn "spike-stale: no green spike recorded (run \`jiva spike\`)"
  elif [[ $s != "$v" ]]; then warn "spike-stale: last green spike on $s, now $v — run \`jiva spike\`"
  else ok "spike fresh ($s)"; fi
}

stophook() { # a Stop hook that says "keep going" is a loop engine
  local f found=""
  for f in "$H/core/settings.json" "$H/plugin/hooks/hooks.json" "$J/settings.json"; do
    [[ -f $f ]] && jq -e '.. | objects | select(has("Stop") or has("SubagentStop"))' "$f" >/dev/null 2>&1 && found+=" ${f#"$H"/}"
  done
  [[ -z $found ]] && ok "no Stop/SubagentStop hook in JIVA settings/plugin" || no "Stop hook (loop engine) in:$found"
  found=""
  for f in "$HOME/.claude/settings.json" "$TARGET/.claude/settings.json" "$TARGET/.claude/settings.local.json"; do
    [[ -f $f ]] && jq -e '.hooks // {} | has("Stop") or has("SubagentStop")' "$f" >/dev/null 2>&1 && found+=" $f"
  done
  [[ -z $found ]] || warn "Stop hook outside JIVA (check it never says keep going):$found"
}

claudemd; caps; nudge; diet "$J/state.json" "(live)"; version; stophook
exit $bad
