#!/usr/bin/env bash
# card — lint a task card before it starts (`just card` runs it before assign; docs/agents/AREAS.md):
# ≤20 lines plus three brief fields, each on its own `Key:` (a `Claim:` line counts as Owned paths, and
# `Done-check:` as Done-when, so older cards still pass). Exit 1 + one line per problem; nothing is assigned.
#   card.sh <file>
set -uo pipefail
f=${1:?usage: card.sh <file>}; bad=0
[[ -s $f ]] || { echo "card: no card at $f" >&2; exit 1; }
n=$(wc -l < "$f"); (( n <= 20 )) || { echo "card $f: $n lines > 20" >&2; bad=1; }
for k in 'Area' 'Owned paths|Claim' 'Done-when|Done-check'; do
  grep -qE "(^|[[:space:]*_])($k)[*_]*:" "$f" ||
    { echo "card $f: missing '${k%%|*}:' — rejected unstarted (Area, Owned paths, Done-when)" >&2; bad=1; }
done
exit $bad
