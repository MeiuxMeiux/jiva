#!/usr/bin/env bash
# digest — the desk's zero-token Monitor tick (`just desk-digest`; core/roles/desk.md). Prints NOTHING when
# nothing changed since the last run, else one line per changed item. A 10-min Monitor on it costs no
# tokens on quiet ticks. Items: pushed (upstream sha) · asks (open ids) · gate (open row ids) ·
# alert (newest notify.log line) · parked (names) · flags (names). Snapshot: .jiva/digest.last.
#   digest.sh [reset]   reset forgets the snapshot (next run prints every non-empty item)
set -uo pipefail
# shellcheck source=core/lib.sh
source "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")/lib.sh"
LAST="$J/digest.last"; mkdir -p "$J"
[[ ${1:-} == reset ]] && { rm -f "$LAST"; exit 0; }
names() { ls "$1" 2>/dev/null | sort | xargs; }
snap() {
  local up a
  up="$(git -C "$TARGET" log -1 --format='%h %s' '@{u}' 2>/dev/null | cut -c1-70)"
  printf 'pushed\t%s\n' "$up"
  a="$(jq -r '.id' "$J/asks/open.jsonl" 2>/dev/null | xargs)"; printf 'asks\t%s\n' "${a:+$(wc -w <<<"$a") open: $a — jiva inbox}"
  a="$("$JIVA_HOME/core/gate.sh" plan 2>/dev/null | grep -oE '^g[0-9a-f]+ \[[a-z]+' | tr -d '[' | xargs)"
  printf 'gate\t%s\n' "${a:+$a — just gate-run}"
  a="$(tail -n 1 "$J/notify.log" 2>/dev/null)"
  [[ $a =~ ^([0-9]+)\ (.*)$ ]] && a="$(date -d "@${BASH_REMATCH[1]}" +%H:%M 2>/dev/null) ${BASH_REMATCH[2]:0:90}"
  printf 'alert\t%s\n' "$a"
  printf 'parked\t%s\n' "$(names "$J/parked")"
  printf 'flags\t%s\n' "$(names "$J/flags")"
}
now="$(snap)"; old="$(cat "$LAST" 2>/dev/null)"
[[ $now == "$old" ]] && exit 0
printf '%s\n' "$now" > "$LAST.tmp" && mv "$LAST.tmp" "$LAST"
# changed keys only; an item that became empty says "cleared"
while IFS=$'\t' read -r k v; do
  o="$(awk -F'\t' -v k="$k" '$1 == k { print $2 }' <<<"$old")"
  [[ $v == "$o" ]] && continue
  [[ -z $v && -z $o ]] && continue
  echo "$(date +%H:%M) $k: ${v:-cleared}"
done <<<"$now"
