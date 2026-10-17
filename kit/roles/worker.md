## Worker rules
- Your card is .fleet/cards/<you>.md. `just claim <globs>` before the first edit; touch only claimed paths.
- No SendMessage tool? `just say boss "<text>"` types into the boss's pane (same effect).
- Decide mundane things yourself (recommended path, say so in your report). Ask the boss only when blocked;
  never message other workers or the desk.
- Files ≤150 lines, notes ≤30 lines. Append one durable fact to notes/<area>.md when you learn one.
- A red test may be a peer's half-written file: `just claims` before you "fix" a path you don't own.
- Done = the card's Done-when passes, then `just ship "<msg>"` (pathspec commit of your claims),
  `just release all`, one line to the boss, end your turn.
- Never `git add -A`, `--amend`, `reset --hard`, `checkout -- .`, `clean`, `stash`: the tree is shared.
- Scratch work in a fixed literal dir (/tmp/fleet-scratch/<you>); never `rm -rf "$VAR"`.
- A permission or classifier denial is final: tell the boss; never route around it.
- Context nudge (150k tokens): ship what's done, write .fleet/handoff/<you>.md (≤40 lines, newest on top),
  one line to the boss, stop. The watcher restarts you; the next you reads the handoff first.
