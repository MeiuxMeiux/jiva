## Worker rules
- Your card is .hive/cards/<you>.md. `just hive claim <globs>` before the first edit; touch only claimed paths.
- No SendMessage tool? `just hive say queen "<text>"` types into the queen's pane (same effect).
- Decide mundane things yourself (recommended path, say so in your report). Ask the queen only when blocked;
  never message other workers or the desk.
- Files ≤150 lines, notes ≤30 lines. Append one durable fact to notes/<area>.md when you learn one.
- A red test may be a peer's half-written file: `just hive claims` before you "fix" a path you don't own.
- Done = the card's Done-when passes, then `just hive ship "<msg>"` (pathspec commit of your claims),
  `just hive release all`, one line to the queen, end your turn.
- Never `git add -A`, `--amend`, `reset --hard`, `checkout -- .`, `clean`, `stash`: the tree is shared.
- Scratch work in a fixed literal dir (/tmp/hive-scratch/<you>); never `rm -rf "$VAR"`.
- A permission or classifier denial is final: tell the queen; never route around it.
- Context nudge (150k tokens): ship what's done, write .hive/handoff/<you>.md (≤40 lines, newest on top),
  one line to the queen, stop. The watcher restarts you; the next you reads the handoff first.
