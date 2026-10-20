#!/usr/bin/env bash
# the session verbs behind `jiva <verb>` (and the `just j-*` wrappers). Identity comes from $JIVA_NAME
# (launcher-set); state lives in the target repo's .jiva (core/lib.sh).
set -euo pipefail
# shellcheck source=core/lib.sh
source "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")/lib.sh"
# shellcheck source=core/asks.sh
source "$JIVA_HOME/core/asks.sh"
# shellcheck source=core/history.sh
source "$JIVA_HOME/core/history.sh"
mkdir -p "$J"/{claims,handoff,rotate,asks}
ME="${JIVA_NAME:-desk}"
log() { board_log "$ME" "$*"; }

claim() { # claim <paths...> — directory-level, refused if it overlaps another session's claim; one claimer at a time
  ( flock 9; claim_locked "$@" ) 9> "$J/claims.lock" || exit 1   # check-then-append is atomic across sessions
}
claim_locked() { # body of claim, runs under claims.lock (exit 1 inside only ends the locked subshell)
  local p q f
  for p in "$@"; do
    p="${p%/}"; p="${p#./}"   # `.`, `..`, /abs or ./x would dodge the overlap test (and ship would sweep the tree)
    [[ -n $p && $p != /* && ! $p =~ (^|/)\.\.?(/|$) ]] || { echo "claim: '$p' must be a repo-relative subpath" >&2; exit 1; }
    for f in "$J"/claims/*; do
      [[ -e $f && $(basename "$f") != "$ME" ]] || continue
      while read -r q; do
        [[ $p == "$q" || $p == "$q"/* || $q == "$p"/* ]] &&
          { echo "claim: $p overlaps $(basename "$f")'s $q" >&2; exit 1; }
      done < "$f"
    done
    grep -qxF -- "$p" "$J/claims/$ME" 2>/dev/null || echo "$p" >> "$J/claims/$ME"
  done
  log "claim $*"; hist claim n=$#; cat "$J/claims/$ME"
}

unclaim() { # unclaim <paths...> — drop exact paths from this session's own claims file (never hand-edit .jiva/claims)
  local p f="$J/claims/$ME" tmp; [[ -e $f ]] || { echo "unclaim: nothing claimed" >&2; exit 1; }
  for p in "$@"; do tmp="$(mktemp)"; grep -vxF -- "${p%/}" "$f" > "$tmp" || true; mv "$tmp" "$f"; done
  log "unclaim $*"; cat "$f"
}

check() { # target's own `just check` if it has one, else JIVA's generic budgets run in the target
  if [[ -f $TARGET/justfile ]] && just -f "$TARGET/justfile" --summary 2>/dev/null | tr ' ' '\n' | grep -qx check
  then just -f "$TARGET/justfile" check; else (cd "$TARGET" && "$JIVA_HOME/core/check.sh"); fi
}

report() { # report <done|blocked|note> <msg> — done is verified by check()
  local st=$1; shift
  if [[ $st == "done" ]]; then check || { echo "report: check failed — not done" >&2; exit 1; }; fi
  log "$st: $*"; hist report st="$st"; echo "reported $st"
}

ask() { ask_new "$@"; }          # ask <question> <options> <default> [class] — typed ask for the desk (core/asks.sh)
answer() { ask_answer "$1" "${2:-}"; }  # answer <id> [text] — desk/keeper; no text applies the default

ship() { # ship <msg> — commit only claimed paths, push under a lock
  local paths keep=() p; mapfile -t paths < <(cat "$J/claims/$ME" 2>/dev/null)
  for p in "${paths[@]}"; do # a gitignored (generated) path in a claim would abort git add
    if git -C "$TARGET" check-ignore -q "$p"; then echo "ship: $p is gitignored, skipped" >&2; else keep+=("$p"); fi
  done
  paths=("${keep[@]}")
  ((${#paths[@]})) || { echo "ship: nothing claimed" >&2; exit 1; }
  (
    flock 9
    cd "$TARGET"
    git add -- "${paths[@]}"
    git diff --cached --quiet -- "${paths[@]}" && { echo "ship: no changes in claimed paths"; exit 0; }
    git commit -q -m "$1" -m "jiva: $ME" -- "${paths[@]}"
    if git remote | grep -qx origin; then git push -q origin HEAD 2>&1 | tail -3; else echo "ship: no origin, not pushed"; fi
    git log --oneline -1; hist ship sha="$(git rev-parse --short HEAD)"
  ) 9> "$J/ship.lock"
  log "ship: $1"
}

handoff() { # handoff <file> — ≤40 lines of pointers (or pipe: printf ... | jiva handoff); marks session for respawn
  local tmp; tmp="$(mktemp)"; cat "${1:-/dev/stdin}" > "$tmp"
  grep -q '[^[:space:]]' "$tmp" || { rm -f "$tmp"
    echo "handoff: empty — pass a file: jiva handoff <file>, or pipe: printf ... | jiva handoff" >&2; exit 1; }
  (( $(wc -l < "$tmp") <= 40 )) || { echo "handoff: over 40 lines" >&2; rm -f "$tmp"; exit 1; }
  mv "$tmp" "$J/handoff/$ME.md"; [[ $ME == desk ]] || touch "$J/rotate/$ME"
  log "handoff written"; hist handoff lines="$(wc -l < "$J/handoff/$ME.md")"; echo "handoff saved; stop now — the watchdog respawns you when idle"
}

inbox() { # recent comb + open desk asks (open.jsonl; desk.tsv retired)
  local b; b="$(board_tail "${1:-15}")"; echo "${b:-(empty)}"
  ask_inbox
}

pending() { # sessions stuck at a native prompt (answer them in their tmux window)
  local out
  out="$(jq -r '.sessions[] | select(.waiting) | "\(.name): \(.waiting) → tmux -L '"$SOCK"' attach -t jiva:\(.name)"' \
    "$J/state.json" 2>/dev/null)" || { echo "(no state yet — is the watchdog up?)"; return; }
  echo "${out:-(nothing waiting)}"
}

cmd="${1:-}"; shift || true
case "$cmd" in
  claim|unclaim|report|ask|answer|ship|handoff|inbox|pending) "$cmd" "$@" ;;
  *) echo "verbs: claim unclaim report ask answer ship handoff inbox pending" >&2; exit 1 ;;
esac
