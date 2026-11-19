#!/usr/bin/env bash
# plugin drift — skills/commands may only name commands that exist (pattern: site/scripts/drift.py).
# FAIL: a `jiva <sub>` in plugin/**/*.md that `bin/jiva help` doesn't list, or a `just <recipe>` that
# `just --list` doesn't list. WARN: CLI subcommands no skill/command mentions (role "Verbs you use" tables,
# commands/jiva-desk.md for keeper verbs) unless in ALLOW. Exit 1 on any FAIL; WARN never fails.
set -uo pipefail
P="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"; HOME_="${JIVA_HOME:-$(dirname "$P")}"
help=$("$HOME_/bin/jiva" help 2>/dev/null)
recs=$(cd "$HOME_" && just --list 2>/dev/null | awk 'NR>1 {print $1}')
[[ -n $help && -n $recs ]] || { echo "FAIL plugin drift: could not read \`jiva help\` or \`just --list\`"; exit 1; }
# help lines look like "  sub [args]  desc" or "  a|b|c   desc"
subs=$(grep -oP '^  \K[a-z][a-z|-]*' <<<"$help" | tr '|' '\n' | sort -u)
mds=$(find -L "$P" -name '*.md' | sort)
# words after `jiva`/`just` not glued to / @ . - (skips /jiva-inbox, jiva@jiva-local)
named() { grep -ohP "(?<![\w/@.-])$1\s+\K[a-z][a-z0-9*-]*" $mds | sort -u; }
bad=0
while read -r s; do
  [[ -z $s ]] && continue
  grep -qx "$s" <<<"$subs" || { echo "FAIL plugin drift: names \`jiva $s\`, not in \`jiva help\`"; bad=1; }
done <<<"$(named jiva)"
# shellcheck disable=SC2053  # unquoted rhs on purpose: globs like j-* allowed
while read -r r; do
  [[ -z $r ]] && continue
  hit=0; for x in $recs; do [[ $x == $r ]] && hit=1; done   # globs like j-* allowed
  (( hit )) || { echo "FAIL plugin drift: names \`just $r\`, not in \`just --list\`"; bad=1; }
done <<<"$(named just)"
ALLOW=""   # keeper-only verbs exempt from WARN; keep empty — list them in commands/jiva-desk.md instead
need=$(comm -23 <(echo "$subs") <(printf '%s\n' help $ALLOW | sort -u))
unnamed=$(comm -23 <(echo "$need") <(named jiva) | tr '\n' ' ')
[[ -n $unnamed ]] && echo "WARN plugin drift: CLI verbs no skill/command mentions: $unnamed"
echo "plugin-check: $(wc -w <<<"$mds") md, jiva $(named jiva | wc -l) named / $(wc -l <<<"$subs") in help," \
  "just $(named just | wc -l) named — $( ((bad)) && echo FAIL || echo ok)"
exit "$bad"
