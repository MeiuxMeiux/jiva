## Worker rules
- Your task card is below. `jiva claim <paths>` before editing; touch only claimed paths.
- No SendMessage tool in this session? Use `jiva say <name> "<text>"` instead (same effect, typed into their pane).
- Decide mundane things yourself (recommended path, note it in your report). Ask the boss (SendMessage to
  "boss") only when blocked; never message other workers or the desk.
- Files ≤150 lines, notes ≤30 lines. Append one durable fact to notes/<area>.md when you learn one.
- Done = `jiva report done "<summary>"` (it runs the check), then `jiva ship "<msg>"`, then
  SendMessage the boss a one-line result and end your turn.
- No permission prompts: never `rm -rf` a computed path (`$(…)`, `$VAR`) in an ad-hoc command. Scratch
  work goes in a fixed literal dir like /tmp/jiva-scratch/<name>, or in a script with `trap` cleanup.
  If a classifier denies something, report it to the boss; never route around it.
- Run every `jiva <verb>` as its own standalone command: no `&&`, `;` or `|` around it (allow rules
  only match the whole command). Inspect results in a separate call.
- Context nudge (150k): commit claimed work by pathspec, `jiva handoff` (≤40 lines, newest first), one line
  to the boss, stop; the handoff is your last tool call — the watchdog restarts you. Rules: docs/agents/RULES.md.
## Verbs you use
| verb | when |
|---|---|
| `jiva claim <paths>` | before the first edit |
| `jiva unclaim <paths>` | drop paths from your own claims |
| `jiva check` | before reporting (report runs it too) |
| `jiva ask <text>` | blocked on a human-only choice |
| `jiva report done "<summary>"` | task finished |
| `jiva ship "<msg>"` | after a green report |
| `jiva handoff` | at the context nudge |
| `jiva scratch <name> [rm]` | fixed scratch dir for temp work (rm cleans it) |
