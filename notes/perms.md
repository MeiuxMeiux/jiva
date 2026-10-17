# perms — permission, trust, auto-mode facts (split from notes/core.md 2026-10-13)

- Asks (core/asks.sh): open.jsonl→answered.jsonl, desk.tsv retired. Only class `decision` expires to its
  default; protected classes (ASK_PROTECTED) wait for a human. Rules/settings: only the human edits them.
- Human's `~/.claude/settings.json` allowlists ~110 Bash prefixes (incl. curl, git add/commit) and
  defaultMode=auto, so most tool calls never prompt. Spike prompts with `--permission-mode default`.
- Auto-mode classifier blocks Claude writing: an allow-returning PermissionRequest hook, a launcher that
  clicks the trust dialog ("Create Unsafe Agents"), a self-respawn/auto-push verbs script and starting
  the WSL keepalive ("Unauthorized Persistence"). Needs human-added allow rules — don't reshape to evade.
- Permission path chosen: no allow-hook. Auto mode + allowlist clears routine calls; what's left prompts
  natively, watchdog flags `waitingFor` + toast, human answers in that pane (`just j-pending`).
- New target: trust dialog once per repo, human accepts in tmux (never auto); heal skips panes showing it.
- perm-relay.sh (opt-in) on timeout or STOP appends `<ts> <session> <tool>` to `.jiva/flags/perm-timeout`
  (last 20 lines), still exits 0 → native prompt; `jiva doctor perm` tests timeout/allow/deny in scratch.
- `.jiva/STOP` (lib.sh `stopped()`): guard (matcher `*`) returns deny JSON "JIVA STOPPED" for every tool;
  session-start injects only "STOPPED: … wait"; statusline prefixes STOPPED; breaker/affinity exit 0 unwritten.
- guard: packs/local/ (human's private roster) → exit 2 for Write/Edit by file_path, and Bash only as a write
  target (rm/mv/cp/tee/touch/mkdir/sed -i/find -delete/`>`/git rm/art+roster scripts); mentions + reads pass.
  Read-only `git stash list|show` pass; any other `git stash` is still denied.
