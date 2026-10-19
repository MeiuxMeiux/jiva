#!/usr/bin/env bash
# mail.sh — send one plain-text mail from jiva@meiuxmeiux.com via Postmark. Key read here, never printed.
#   scripts/mail.sh [--dry-run] <to> <subject> <bodyfile|->      (- = stdin)
#   scripts/mail.sh --status <MessageID>                         (Postmark delivery events for a sent id)
# Prints what it did; non-zero on any surprise. Every real send appends to .jiva/state/mail.sent
# ("<epoch> <MessageID> <to> <subject>") so a retry can see it went. Key file: $JIVA_MAIL_KEY_FILE
# (default $JIVA_KEYS_DIR/iblis-postmark.token — the Postmark server that owns meiuxmeiux.com).
set -euo pipefail
H="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
dry=0; [[ ${1:-} == --dry-run ]] && { dry=1; shift; }
# shellcheck source=keys.sh
source "$H/scripts/keys.sh"; keyfile="${JIVA_MAIL_KEY_FILE:-$KEYS_DIR/iblis-postmark.token}"
if [[ ${1:-} == --status ]]; then
  [[ -n ${2:-} ]] || { sed -n '4p' "$0" >&2; exit 2; }; load_key POSTMARK_TOKEN "$keyfile"
  curl -sS --max-time 30 "https://api.postmarkapp.com/messages/outbound/$2/details" -H 'Accept: application/json' \
    -H "X-Postmark-Server-Token: ${POSTMARK_TOKEN//[[:space:]]/}" \
    | jq -r '"status=\(.Status // .Message) to=\(.Recipients[0] // "-") " + ([.MessageEvents[]? | "\(.Type)@\(.ReceivedAt)"] | join(" "))'
  exit 0
fi
(( $# == 3 )) || { sed -n '3p' "$0" >&2; exit 2; }
to="$1"; subject="$2"; bodyfile="$3"
from="${JIVA_MAIL_FROM:-JIVA <jiva@meiuxmeiux.com>}"; reply="${JIVA_MAIL_REPLY_TO:-jiva@meiuxmeiux.com}"
[[ $to =~ ^[^[:space:]@]+@[^[:space:]@]+\.[^[:space:]@]+$ ]] || { echo "mail: bad recipient" >&2; exit 2; }
if [[ $bodyfile == - ]]; then body="$(cat)"; else body="$(< "$bodyfile")"; fi
[[ -n $body ]] || { echo "mail: empty body" >&2; exit 2; }
payload="$(jq -n --arg f "$from" --arg t "$to" --arg r "$reply" --arg s "$subject" --arg b "$body" \
  '{From:$f, To:$t, ReplyTo:$r, Subject:$s, TextBody:$b, MessageStream:"outbound", Tag:"jiva-desk"}')"
if (( dry )); then
  printf 'mail --dry-run: from=%s to=%s subject=%s bytes=%s key=%s (%s)\n' \
    "$from" "$to" "$subject" "${#body}" "$(basename "$keyfile")" "$([[ -r $keyfile ]] && echo readable || echo MISSING)"
  exit 0
fi
load_key POSTMARK_TOKEN "$keyfile"
resp="$(curl -sS --max-time 30 -X POST https://api.postmarkapp.com/email \
  -H 'Accept: application/json' -H 'Content-Type: application/json' \
  -H "X-Postmark-Server-Token: ${POSTMARK_TOKEN//[[:space:]]/}" --data-binary "$payload")"
code="$(jq -r '.ErrorCode // "?"' <<<"$resp")"
if [[ $code != 0 ]]; then echo "mail: FAIL ErrorCode=$code $(jq -r '.Message // empty' <<<"$resp")" >&2; exit 1; fi
id="$(jq -r .MessageID <<<"$resp")"; mkdir -p "$H/.jiva/state"
printf '%s %s %s %s\n' "$(date +%s)" "$id" "$to" "$subject" >> "$H/.jiva/state/mail.sent"
echo "mail: sent to=$to subject=$subject id=$id"
