#!/usr/bin/env bash
# status line — writes numbers-only state to .jiva/state/<name>.json; prints one short line.
in="$(cat)"
# shellcheck source=core/lib.sh
JIVA_TARGET="${CLAUDE_PROJECT_DIR:-${JIVA_TARGET:-}}"; source "$(dirname "$(readlink -f "$0")")/../lib.sh"
root="$TARGET"; dir="$J/state"; mkdir -p "$dir"
name="${JIVA_NAME:-$(jq -r '.session_name // .session_id' <<<"$in")}"; name="${name//[^A-Za-z0-9_.-]/_}"   # a path component, never a path
jq -c '{ts: (now|floor), tok: (.context_window.total_input_tokens // 0),
        pct: (.context_window.used_percentage // 0), usd: (.cost.total_cost_usd // 0),
        q5h: (.rate_limits.five_hour.used_percentage // null),
        q7d: (.rate_limits.seven_day.used_percentage // null)}' <<<"$in" > "$dir/$name.tmp" &&
  mv "$dir/$name.tmp" "$dir/$name.json"
if [[ $name == boss ]]; then   # refresh the boss lease (no-op if another fresh holder has it)
  # shellcheck source=core/lease.sh
  source "$JIVA_HOME/core/lease.sh"; lease_take "$(jq -r '.session_id // "?"' <<<"$in")" "$(lease_pane)" || true
fi
bar="$(sed 's/ · asks [0-9]*//; s/^STOPPED · //' "$root/.jiva/bar" 2>/dev/null)"   # asks come fresh from the file below
asks=$( (wc -l < "$J/asks/open.jsonl") 2>/dev/null || echo 0)   # open-ask count at zero tokens
rot=""   # desk rotates only when idle: tokens, not %, so a 1M window still rotates at ~150k
nudge="${JIVA_NUDGE:-150000}"
[[ ${JIVA_ROLE:-} == desk ]] && (( asks == 0 )) && jq -e --argjson n "$nudge" '(.context_window.total_input_tokens // 0) >= $n' <<<"$in" >/dev/null &&
  rot=" · ROTATE: ctx ≥$((nudge / 1000))k, no asks — jiva handoff now"
jq -r --arg r "$rot" --argjson s "$(stopped && echo true || echo false)" --arg n "${JIVA_ROLE:-?}:$name" --arg b "$bar" --argjson a "$asks" \
  '"\(if $s then "STOPPED · " else "" end)\($n) · \((.context_window.total_input_tokens // 0) / 1000 | floor)k\(if $b == "" then "" else " · " + $b end)\(if $a > 0 then " · asks \($a)" else "" end)\($r)"' <<<"$in"
