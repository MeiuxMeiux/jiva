#!/usr/bin/env bash
# SessionStart — boot payload: role card + task card + handoff for $JIVA_NAME (all optional).
# Launcher sets JIVA_ROLE (desk|boss|worker) and JIVA_NAME. Budget: keep the sum < ~1.5k tokens.
# shellcheck source=core/lib.sh
JIVA_TARGET="${CLAUDE_PROJECT_DIR:-${JIVA_TARGET:-}}"; source "$(dirname "$(readlink -f "$0")")/../lib.sh"
stopped && { jq -n '{hookSpecificOutput: {hookEventName: "SessionStart", additionalContext: "STOPPED: .jiva/STOP present, do nothing, wait"}}'; exit 0; }
[[ -n "${JIVA_ROLE:-}" ]] || exit 0
in="$(cat)"
recap() { # last ship · open asks · flags — three lines, numbers + names only
  local s n f
  s="$(jq -r 'select(.kind == "ship") | "\(.sha) by \(.who) \((now - .ts) / 60 | floor)m ago"' "$J/history.jsonl" 2>/dev/null | tail -1)"
  printf 'recap: last ship %s\n' "${s:-$(git -C "$TARGET" log -1 --format='%h (%cr)' 2>/dev/null || echo none)}"
  n=$(cat "$J/asks/open.jsonl" 2>/dev/null | grep -c '')
  printf 'recap: open asks %s%s\n' "$n" "$( ((n)) && echo ' — `jiva inbox`')"
  f="$(ls "$J/flags" 2>/dev/null | tr '\n' ' ')"; printf 'recap: flags %s\n\n' "${f:-none}"
}
if [[ ${JIVA_NAME:-} == boss && -z ${JIVA_DOCTOR:-} ]]; then   # boss lease (JIVA_DOCTOR=1: payload test, never touch it) (core/lease.sh): take it, or be refused as the extra
  # shellcheck source=core/lease.sh
  source "$JIVA_HOME/core/lease.sh"; sid="$(jq -r '.session_id // "?"' <<<"$in" 2>/dev/null)"; pane="$(lease_pane)"
  held="$(lease_held "$sid" "$pane")" && { mkdir -p "$J/lease"; [[ $pane == - ]] || : > "$J/lease/extra.$pane"; }
  [[ -n $held ]] || lease_take "$sid" "$pane"
fi
{
  [[ -n ${held:-} ]] && printf 'lease held by %s — you are an extra boss. End your turn now; do nothing else.\n\n' "$held"
  boss=boss; [[ $(cat "$J/profile" 2>/dev/null) == solo ]] && boss="${JIVA_DESK:-desk} (solo profile: the desk is the boss)"
  printf 'You are JIVA %s "%s". Desk session: %s. Boss session: %s.\n\n' \
    "$JIVA_ROLE" "${JIVA_NAME:-?}" "${JIVA_DESK:-desk}" "$boss"
  [[ $JIVA_ROLE == desk ]] && recap   # the desk returns with a 3-line recap
  cat "$JIVA_HOME/core/roles/$JIVA_ROLE.md" 2>/dev/null
  for f in "$J/tasks/$JIVA_NAME.md" "$J/handoff/$JIVA_NAME.md"; do
    [[ -s "$f" ]] && printf '\n## %s\n' "${f#"$TARGET"/}" && cat "$f"
  done
} | jq -Rs '{hookSpecificOutput: {hookEventName: "SessionStart", additionalContext: .}}'
