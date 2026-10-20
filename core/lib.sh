# shellcheck shell=bash
# lib — sourced by every core script and hook. Two roots:
#   JIVA_HOME  this checkout (code: core/, roles, settings template) — from BASH_SOURCE, symlinks resolved
#   TARGET     the project the hive works on: $JIVA_TARGET, else git toplevel of $PWD, else $PWD.
#              A JIVA_TARGET inherited from a hive pane (== JIVA_PANE_TARGET, set by $J/settings.json env)
#              yields to $PWD's git toplevel when PWD is outside it (`jiva init` in another repo).
#   J          $TARGET/.jiva (all runtime state)   SOCK  tmux socket: `jiva` for JIVA_HOME itself,
#              `jiva-<basename of TARGET>` otherwise, so a target hive never touches ours.
# UTF-8: output carries · → ≥ …; with LANG unset bash/printf escape them. Prefer C.UTF-8, else en_US.UTF-8.
if [[ ${LC_ALL:-${LC_CTYPE:-${LANG:-}}} != *[Uu][Tt][Ff]* ]]; then
  for _l in C.UTF-8 C.utf8 en_US.UTF-8 en_US.utf8; do
    grep -qixF "$_l" <(locale -a 2>/dev/null) && { export LC_ALL=$_l; break; }
  done; unset _l
fi
jiva_env() { # ${XDG_CONFIG_HOME:-~/.config}/jiva/env: KEY=VALUE lines, JIVA_* only, parsed (never sourced); env wins
  local f="${XDG_CONFIG_HOME:-${HOME:-}/.config}/jiva/env" line k v
  [[ -r $f ]] || return 0
  while IFS= read -r line || [[ -n $line ]]; do
    [[ $line =~ ^[[:space:]]*(export[[:space:]]+)?(JIVA_[A-Z0-9_]+)=(.*)$ ]] || continue
    k=${BASH_REMATCH[2]}; v=${BASH_REMATCH[3]}
    case $k in JIVA_HOME|JIVA_TARGET|JIVA_PANE_TARGET|JIVA_NAME|JIVA_ROLE) continue ;; esac   # identity stays per-process
    [[ $v =~ ^\"(.*)\"$ || $v =~ ^\'(.*)\'$ ]] && v=${BASH_REMATCH[1]}
    [[ -n ${!k+x} ]] || export "$k=$v"
  done < "$f"
}
jiva_env
JIVA_HOME="$(cd "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")/.." && pwd)"
TARGET="${JIVA_TARGET:-$(git rev-parse --show-toplevel 2>/dev/null || pwd)}"
TARGET="$(realpath "$TARGET")"
if [[ -n ${JIVA_PANE_TARGET:-} && ${JIVA_TARGET:-} == "$JIVA_PANE_TARGET" ]] &&
   _top="$(git rev-parse --show-toplevel 2>/dev/null)" && [[ $_top/ != "$TARGET"/* ]]; then
  TARGET="$(realpath "$_top")"
fi; unset _top
J="$TARGET/.jiva"
if [[ $TARGET == "$JIVA_HOME" ]]; then SOCK=jiva; else SOCK="jiva-$(basename "$TARGET")"; fi
export JIVA_HOME JIVA_TARGET="$TARGET"
T() { tmux -L "$SOCK" "$@"; }
stopped() { [[ -e $J/STOP ]]; }   # .jiva/STOP: every hook and the watchdog stand down

hooks_mode() { # plugin|settings — JIVA_HOOKS overrides; else plugin iff installed at user scope (no side effects)
  case "${JIVA_HOOKS:-}" in plugin|settings) echo "$JIVA_HOOKS"; return ;; esac
  if "$JIVA_HOME/plugin/install.sh" status -q; then echo plugin; else echo settings; fi
}

render_settings() { # core/settings.json, hooks pinned to JIVA_HOME → $J/settings.json; plugin mode keeps statusLine only
  mkdir -p "$J"; chmod go-rwx "$J" 2>/dev/null || true   # runtime state (asks, perm dumps, comb) is owner-only
  jq --arg h "$JIVA_HOME" --arg m "$(hooks_mode)" --arg t "$TARGET" 'walk(if type == "string"
      then gsub("\"\\$CLAUDE_PROJECT_DIR\"/core"; "\"" + $h + "\"/core") else . end)
      | if $m == "plugin" then del(.hooks) else . end | .env.JIVA_PANE_TARGET = $t' \
    "$JIVA_HOME/core/settings.json" > "$J/settings.tmp" && mv "$J/settings.tmp" "$J/settings.json"
}

preflight() { # one line per missing tool; return 1 when a required one is missing (jiva init / up)
  local t bad=0
  (( BASH_VERSINFO[0] >= 4 )) || { echo "missing: bash ≥ 4 (this is $BASH_VERSION; macOS: brew install bash)"; bad=1; }
  for t in tmux jq flock git claude; do
    command -v "$t" >/dev/null || { echo "missing: $t (required)"; bad=1; }
  done
  for t in python3 setsid; do command -v "$t" >/dev/null || echo "missing: $t (optional: dashboard only)"; done
  return $bad
}

init_target() { # jiva init — make $TARGET hive-ready; never overwrites an existing CLAUDE.md
  mkdir -p "$J"
  grep -qxF '.jiva/' "$TARGET/.gitignore" 2>/dev/null || echo '.jiva/' >> "$TARGET/.gitignore"
  local b=" Files ≤150 lines; notes ≤30 lines."; [[ ${JIVA_BUDGETS:-1} != 0 ]] || b=""
  [[ -e $TARGET/CLAUDE.md ]] || cat > "$TARGET/CLAUDE.md" <<MD
# JIVA hive
- This repo is worked by a JIVA hive (queen + workers); runtime state lives in \`.jiva/\` (gitignored).
- Verbs: \`jiva claim|report|ask|ship|handoff|inbox|pending\`. Runtime: \`jiva up [n]\` / \`jiva down\`.
- Claim paths before editing; touch only claimed paths.$b
MD
  echo "jiva: $TARGET ready (socket $SOCK)"
  [[ ${JIVA_BUDGETS:-1} == 0 ]] || echo "Budgets: CLAUDE.md asks files ≤150 lines, notes ≤30 and \`jiva report done\` checks them; JIVA_BUDGETS=0 (env or ~/.config/jiva/env) turns that off."
  echo "Left uncommitted: .gitignore (.jiva/) + CLAUDE.md — review and commit them yourself."
  echo "First \`jiva up\` in a new repo stops at Claude's workspace-trust dialog once; accept it in that"
  echo "tmux window (tmux -L $SOCK a). JIVA never auto-accepts it."
}

board_log() { # name text… → "HH:MM name text<TAB>epoch" in comb.log (one line, under comb.lock ≤1s; never blocks a verb)
  local t="${*:2}"; { flock -w 1 8; printf '%s %-6s %s\t%s\n' "$(date +%H:%M)" "$1" "${t//$'\t'/ }" "$(date +%s)" >> "$J/comb.log"
  } 8>> "$J/comb.lock" 2>/dev/null || true; }
board_tail() { # n → last n comb lines younger than JIVA_MSG_TTL s (6h), stamps stripped; unstamped legacy lines kept
  { tail -n 2000 "$J/comb.log" 2>/dev/null || true; } | awk -F'\t' -v now="$(date +%s)" -v ttl="${JIVA_MSG_TTL:-21600}" \
    'NF < 2 || $NF !~ /^[0-9]+$/ { print; next } now - $NF <= ttl { print $1 }' | tail -n "$1"; }
