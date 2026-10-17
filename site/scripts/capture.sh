#!/usr/bin/env bash
# hero capture — READ-ONLY snapshots of the live fleet for site/src/hero/frames.txt (the hero is a real recording).
# Every 5s for ~2 min: the watchdog bar (tmux status source .jiva/bar, plus the watchdog pane's last
# line via capture-pane -p), `jiva status`, `jiva inbox 8`. Never attaches, never sends keys.
# Redacts token-like strings, absolute paths, commit hashes, branch names; inbox bodies trimmed.
# Usage: capture.sh [seconds=120] [interval=5]
set -uo pipefail
ROOT=$(cd "$(dirname "$0")/../.." && pwd)
OUT="$ROOT/site/src/hero/frames.txt"
DUR=${1:-120} STEP=${2:-5}
J="$ROOT/bin/jiva"

scrub() {
  sed -E \
    -e 's/(sk-[A-Za-z0-9_-]{8,}|gh[pousr]_[A-Za-z0-9]{8,}|xox[a-z]-[A-Za-z0-9-]+|AKIA[0-9A-Z]{12,})/[redacted]/g' \
    -e 's/[A-Za-z0-9+_=-]{32,}/[redacted]/g' \
    -e 's#(~|/)(home|root|var|tmp|mnt|etc|usr|opt|srv)(/[^[:space:]]*)?#[path]#g' \
    -e 's/\b[0-9a-f]{7,40}\b/[sha]/g' \
    -e 's/\b(branch [A-Za-z0-9._\/-]+|origin\/[A-Za-z0-9._\/-]+)/[branch]/g' \
    -e 's/[[:space:]]+$//'
}

{
  echo "# jiva hero capture $(date -u +%Y-%m-%dT%H:%MZ) · every ${STEP}s for ${DUR}s · read-only, redacted"
  n=0 end=$(( $(date +%s) + DUR ))
  while [ "$(date +%s)" -lt "$end" ]; do
    n=$((n + 1))
    echo "=== frame $n $(date -u +%H:%M:%S)"
    echo "bar: $(cat "$ROOT/.jiva/bar" 2>/dev/null | head -1)"
    pane=$(tmux -L jiva capture-pane -p -t jiva:watchdog 2>/dev/null | grep -v '^[[:space:]]*$' | tail -1)
    [ -n "$pane" ] && echo "watchdog: $pane"
    echo "status:"; "$J" status 2>/dev/null | sed 's/^/  /'
    echo "inbox:"
    "$J" inbox 8 2>/dev/null | grep -E '^[0-9]{2}:[0-9]{2} ' \
      | awk '{ msg=""; for (i=3;i<=NF;i++) msg=msg (i>3?" ":"") $i; printf "  %s %-6s %.70s\n", $1, $2, msg }'
    sleep "$STEP"
  done
} | scrub > "$OUT.tmp" && mv "$OUT.tmp" "$OUT"
echo "capture: $(grep -c '^=== frame' "$OUT") frames → ${OUT#"$ROOT"/}"
