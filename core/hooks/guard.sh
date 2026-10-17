#!/usr/bin/env bash
# guard — PreToolUse hook (matcher *): .jiva/STOP denies every tool. Bash|Skill: Shared-tree git safety: workers commit claimed paths via `jiva ship`,
# so deny the commands that sweep, hide or rewrite other sessions' work. Loop engines (Skill loop|goal, a Bash
# `claude … /loop|/goal`) are capped: the watchdog does the waking. packs/local/ (the human's private roster):
# Write/Edit by file_path, Bash only as a write target (rm/mv/cp/tee/touch/mkdir/sed -i/> /git rm/art+roster
# scripts) — a mere mention (echo, heredoc body, comment) passes. Read-only `git stash list|show` pass. Exit 2 + reason.
in="$(cat)"
# shellcheck source=core/lib.sh
JIVA_TARGET="${CLAUDE_PROJECT_DIR:-${JIVA_TARGET:-}}"; source "$(dirname "$(readlink -f "$0")")/../lib.sh"
if stopped; then   # .jiva/STOP: deny every tool (matcher "*") until the human removes it
  echo '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"deny","permissionDecisionReason":"JIVA STOPPED"}}'; exit 0
fi
loop() { echo "JIVA: loop engines are capped — the watchdog wakes you" >&2; exit 2; }
mine() { echo "JIVA guard: packs/local is the human's — never write, overwrite or delete under it" >&2; exit 2; }
PL='(^|[^A-Za-z0-9_.-])packs/local(/|[^A-Za-z0-9_.-]|$)'
tool="$(jq -r '.tool_name // ""' <<<"$in")"
if [[ $tool =~ ^(Write|Edit|MultiEdit|NotebookEdit)$ ]]; then
  [[ $(jq -r '.tool_input | .file_path // .notebook_path // ""' <<<"$in") =~ $PL ]] && mine
  exit 0
fi
if [[ $tool == Skill ]]; then
  [[ $(jq -r '.tool_input.skill // "" | ltrimstr("/")' <<<"$in") =~ ^(loop|goal)$ ]] && loop
  exit 0
fi
cmd="$(jq -r '.tool_input.command // ""' <<<"$in")"
s='[[:space:]]'; e="($s|\$)"; pre="^$s*\\(?$s*([A-Za-z_][A-Za-z0-9_]*=[^ ]*$s+)*(sudo$s+)?([^ ]*/)?"
W='(rm|rmdir|mv|cp|tee|touch|mkdir|ln|install|truncate|dd|rsync|chmod|chown|unlink|shred)'
deny() { echo "JIVA guard: $1 — commit claimed paths with \`jiva ship\` instead" >&2; exit 2; }
while IFS= read -r seg; do   # each simple command (or heredoc line); only its leading command word counts
  [[ $seg =~ ^$s*\(?$s*([A-Za-z_][A-Za-z0-9_]*=[^ ]*$s+)*([^ ]*/)?claude$s.*/(loop|goal)([^A-Za-z0-9_-]|$) ]] && loop
  if [[ $seg =~ $PL ]]; then   # roster path present: deny only when it is a write target
    [[ $seg =~ \>\>?$s*[\"\']?[^\ ]*packs/local ]] && mine
    [[ $seg =~ ${pre}$W$s ]] && mine
    [[ $seg =~ ${pre}sed$s.*(-i|--in-place) || $seg =~ ${pre}find$s.*-delete ]] && mine
    [[ $seg =~ ${pre}git$s.*(rm|mv|clean|checkout|restore)$s ]] && mine
    [[ $seg =~ ${pre}(jiva|just)$s+(roster|art) || $seg =~ (art-gen|art-post|art|roster)\.(sh|py)$e ]] && mine
  fi
  rest="$(sed -nE "s/^$s*\(?$s*([A-Za-z_][A-Za-z0-9_]*=[^ ]*$s+)*git(($s+-[Cc]$s+[^ ]+)|($s+--[a-z-]+=[^ ]+))*$s+//p" <<<"$seg")"
  [[ -n $rest ]] || continue
  [[ $rest =~ ^add($s.*)?$s(-A|--all|\.|:/)$e ]] && deny "git add -A/. sweeps other sessions' files"
  [[ $rest =~ ^stash$e && ! $rest =~ ^stash$s+(list|show)$e ]] && deny "git stash hides other sessions' work"
  [[ $rest =~ ^switch$e ]] && deny "git switch leaves the shared branch"
  [[ $rest =~ ^checkout$e && ! $rest =~ $s--$e ]] && deny "git checkout <branch> leaves the shared branch (use \`checkout -- <path>\`)"
  [[ $rest =~ ^reset($s.*)?$s--hard$e ]] && deny "git reset --hard discards other sessions' work"
  [[ $rest =~ ^push($s.*)?$s(--force[a-z-]*(=[^ ]*)?|-[a-zA-Z]*f[a-zA-Z]*|\+[^ ]+)$e ]] && deny "force push rewrites shared history"
done < <(tr ';&|' '\n\n\n' <<<"$cmd")
exit 0
