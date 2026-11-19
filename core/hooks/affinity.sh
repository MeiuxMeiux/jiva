#!/usr/bin/env bash
# affinity — PostToolUse hook. Edit/Write/MultiEdit → append `ts \t soul \t depth-2 dir` (relative to
# TARGET) to .jiva/affinity.tsv; `jiva pick` reads it. Table kept ≤2000 rows (oldest dropped). Never blocks.
in="$(cat)"
# shellcheck source=core/lib.sh
JIVA_TARGET="${CLAUDE_PROJECT_DIR:-${JIVA_TARGET:-}}"; source "$(dirname "$(readlink -f "$0")")/../lib.sh"
stopped && exit 0   # .jiva/STOP: no table writes
case "$(jq -r '.tool_name // ""' <<<"$in")" in Edit|Write|MultiEdit) ;; *) exit 0 ;; esac
f="$(jq -r '.tool_input.file_path // ""' <<<"$in")"; [[ -n $f && -n ${JIVA_NAME:-} ]] || exit 0
[[ $f == /* ]] || f="$TARGET/$f"
f="$(realpath -m "$f")"; [[ $f == "$TARGET"/* ]] || exit 0
rel="${f#"$TARGET"/}"; dir="$(dirname "$rel")"; dir="$(cut -d/ -f1-2 <<<"$dir")"
mkdir -p "$J"; t="$J/affinity.tsv"
printf '%s\t%s\t%s\n' "$(date +%s)" "$JIVA_NAME" "$dir" >> "$t"
if (( $(wc -l < "$t") > 2000 )); then tail -n 2000 "$t" > "$t.tmp.$$" && mv "$t.tmp.$$" "$t"; fi
exit 0
