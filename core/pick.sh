#!/usr/bin/env bash
# pick — `jiva pick <paths…>`: best IDLE worker for these paths ("same soul, same area", docs/history/PLAN.md).
# Score = Σ over the worker's .jiva/affinity.tsv rows whose depth-2 dir matches a path's of 0.5^age_days.
# Candidates: state.json sessions named wN with status idle and no .jiva/parked/<name>.
# Ties or no history → lowest-numbered idle worker. Prints the name; exit 1 if nobody is idle.
set -euo pipefail
# shellcheck source=core/lib.sh
source "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")/lib.sh"
(( $# )) || { echo "usage: jiva pick <paths…>" >&2; exit 2; }
[[ -s $J/state.json ]] || { echo "(no state yet: run jiva up)" >&2; exit 1; }
dirs=()
for p in "$@"; do
  [[ $p == /* ]] && p="$(realpath -m "$p")" && p="${p#"$TARGET"/}"
  [[ -d $TARGET/$p ]] && d="${p%/}" || d="$(dirname "$p")"
  dirs+=("$(cut -d/ -f1-2 <<<"$d")")
done
idle="$(jq -r '.sessions[]? | select(.status == "idle") | .name | select(test("^w[0-9]+$"))' \
  "$J/state.json" 2>/dev/null | while read -r w; do [[ -e $J/parked/$w ]] || echo "$w"; done | sort -V)"
[[ -n $idle ]] || { echo "pick: no idle worker" >&2; exit 1; }
{ printf '%s\n' "$idle" | sed 's/^/W\t/'; printf 'D\t%s\n' "${dirs[@]}"; { cat "$J/affinity.tsv" 2>/dev/null || true; }; } |
  awk -F'\t' -v now="$(date +%s)" '
    $1 == "W" { n++; w[n] = $2; s[$2] = 0; next }
    $1 == "D" { want[$2] = 1; next }
    ($2 in s) && ($3 in want) { s[$2] += 0.5 ^ ((now - $1) / 86400) }
    END { b = w[1]; for (i = 2; i <= n; i++) if (s[w[i]] > s[b] + 1e-9) b = w[i]; print b }'
