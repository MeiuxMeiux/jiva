#!/usr/bin/env bash
# statusline — Claude Code statusLine hook. Reads the status JSON on stdin, writes numbers only to
# .fleet/state/<name>.json {ts, tok, pct, usd, q5h, q7d} (watch.sh reads tok), prints one short bar:
#   w1 · 42k · 5h 12% · 7d 30%
# name = $FLEET_NAME (set by fleet.sh), else the session name/id. Tokens, not %: a 1M window at 85% is 850k.
set -uo pipefail
in="$(cat)"
dir="$(jq -r '.workspace.project_dir // .cwd // empty' <<<"$in" 2>/dev/null)"
ROOT="${FLEET_ROOT:-${CLAUDE_PROJECT_DIR:-$(git -C "${dir:-.}" rev-parse --show-toplevel 2>/dev/null || pwd)}}"
S="$ROOT/.fleet/state"; mkdir -p "$S"
name="${FLEET_NAME:-$(jq -r '.session_name // .session_id // "desk"' <<<"$in" 2>/dev/null)}"
name="${name//[^A-Za-z0-9_.-]/_}"; [[ -n $name ]] || name=desk   # a path component, never a path
jq -c '{ts: (now | floor), tok: (.context_window.total_input_tokens // 0),
        pct: (.context_window.used_percentage // 0), usd: (.cost.total_cost_usd // 0),
        q5h: (.rate_limits.five_hour.used_percentage // null),
        q7d: (.rate_limits.seven_day.used_percentage // null)}' <<<"$in" > "$S/$name.tmp" 2>/dev/null &&
  mv "$S/$name.tmp" "$S/$name.json" || rm -f "$S/$name.tmp"
jq -r --arg n "$name" '"\($n) · \((.context_window.total_input_tokens // 0) / 1000 | floor)k"
  + (if .rate_limits.five_hour.used_percentage then " · 5h \(.rate_limits.five_hour.used_percentage | floor)%" else "" end)
  + (if .rate_limits.seven_day.used_percentage then " · 7d \(.rate_limits.seven_day.used_percentage | floor)%" else "" end)' \
  <<<"$in" 2>/dev/null || echo "$name"
