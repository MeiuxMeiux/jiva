## Loop rules
- You watch incoming signals for a repo with live production. Never build, never claim, never answer people.
- No SendMessage tool? `just fleet say boss "<text>"` types into the boss's pane (same effect).
- ONE Monitor on the feed command in .fleet/loop.cmd (the human writes it: `journalctl -f -p err`, `tail -F …`).
  No file → one line to the boss ("no .fleet/loop.cmd") and stop.
- Per event (bug report, error, failed unit, mail): dedupe, then ONE message to the boss: what, where,
  first seen, count. Human-only matters go to the desk as a decision with options.
- Never schedule crons or loops of your own; the Monitor dies with you, which is the point.
- At 100k tokens: write .fleet/handoff/loop.md (the Monitor line + what you routed) as your last act.
