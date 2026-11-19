#!/usr/bin/env bash
# doctor-plugin — plugin mode vs settings mode, in a scratch CLAUDE_CONFIG_DIR + scratch target (never ~/.claude):
# installed → `jiva plugin status` 0 and rendered settings have statusLine but no "hooks" (no double-fire);
# uninstalled → status 1 and hooks back; JIVA_HOOKS overrides; plugin wrappers resolve TARGET from
# CLAUDE_PROJECT_DIR (not $PWD) and see JIVA_ROLE/JIVA_NAME. Prints ok/FAIL; exit 1 on any FAIL.
set -uo pipefail
H="$(cd "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")/.." && pwd)"
S="$(mktemp -d /tmp/jiva-doctor-plugin-XXXXXX)"; trap 'rm -rf "$S"' EXIT
mkdir -p "$S/cfg" "$S/tgt/.jiva/tasks"
export CLAUDE_CONFIG_DIR="$S/cfg" JIVA_TARGET="$S/tgt"; unset JIVA_HOOKS
bad=0
ok() { printf 'ok    plugin %s\n' "$1"; }
no() { printf 'FAIL  plugin %s\n' "$1"; bad=1; }
t() { local l=$1; shift; if "$@"; then ok "$l"; else no "$l"; fi; }
render() { (source "$H/core/lib.sh" && render_settings) && cat "$S/tgt/.jiva/settings.json"; }
hooks_in() { render | jq -e 'has("hooks") and has("statusLine")' >/dev/null; }
status_only() { render | jq -e '(has("hooks") | not) and has("statusLine")' >/dev/null; }
st() { "$H/core/jiva.sh" plugin status -q; }
nst() { ! st; }

[[ $(realpath "$CLAUDE_CONFIG_DIR") != $(realpath ~/.claude) ]] || { no "scratch config is ~/.claude — refusing"; exit 1; }
t "uninstalled: status exits 1" nst
t "uninstalled: settings carry hooks" hooks_in
JIVA_HOOKS=plugin t "JIVA_HOOKS=plugin drops hooks" status_only
printf 'MARK-%s\n' "$$" > "$S/tgt/.jiva/tasks/w7.md"
out="$(cd / && CLAUDE_PROJECT_DIR="$S/tgt" JIVA_TARGET=/nonexistent JIVA_ROLE=worker JIVA_NAME=w7 \
  "$H/plugin/hooks/session-start.sh" </dev/null 2>/dev/null | jq -r '.hookSpecificOutput.additionalContext')"
t "wrapper: TARGET from CLAUDE_PROJECT_DIR + role/name env" grep -q "worker \"w7\".*MARK-$$" <<<"$(tr '\n' ' ' <<<"$out")"
sk() { (cd "$1" && "$H/core/check.sh" skills) >/dev/null; }   # plugin skills must stay links into core/roles
mkdir -p "$S/sk/core/roles" "$S/sk/plugin/skills/a" && git -C "$S/sk" init -q && echo r > "$S/sk/core/roles/a.md"
ln -s ../../../core/roles/a.md "$S/sk/plugin/skills/a/SKILL.md"; t "skills: symlink into core/roles passes" sk "$S/sk"
rm "$S/sk/plugin/skills/a/SKILL.md"; echo r > "$S/sk/plugin/skills/a/SKILL.md"
t "skills: plain-file SKILL.md FAILs" eval '! sk "$S/sk"'
out="$(cd "$H" && core/check.sh skills)"   # the real repo: each failing skill is its own red FAIL line
if [[ -z $out ]]; then ok "skills: every repo SKILL.md links into core/roles"
else while read -r l; do no "${l#FAIL plugin }"; done <<<"$out"; fi
if ! command -v claude >/dev/null; then ok "install round-trip: no claude on PATH (skipped)"; exit $bad; fi
"$H/plugin/install.sh" install >/dev/null 2>&1 || no "install into scratch config failed"
t "installed: status exits 0" st
t "installed: settings statusLine only (no hooks)" status_only
JIVA_HOOKS=settings t "JIVA_HOOKS=settings overrides plugin" hooks_in
"$H/plugin/install.sh" uninstall >/dev/null 2>&1 || no "uninstall from scratch config failed"
t "uninstalled again: status exits 1" nst
t "uninstalled again: hooks back" hooks_in
exit $bad
