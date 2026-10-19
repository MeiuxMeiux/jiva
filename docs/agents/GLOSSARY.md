# GLOSSARY — the bee words and what they are (read once; every other doc assumes these)
JIVA is a hive. Bee words name the parts so a reader, human or model, can guess a role from its name.
Where no bee word is faithful, the plain engineering word stays. Renamed 2026-10-19 (alpha); old names in brackets.

- **hive** [fleet] — every session JIVA runs for one repo, on its private tmux server (`tmux -L jiva-<repo>`).
- **keeper** [human] — you. Sits outside the hive, answers asks, runs the KEEPER-only lines. Never a session.
- **cell** [seat] — one slot in the hive that holds a session: `desk`, `queen`, `w1`…`wN`. Bodies die; the cell stays.
- **body / soul** — body: one Claude Code session. soul: the name, color and avatar it wears (jīva = soul).
  The watchdog swaps bodies before 200k context and never swaps souls.
- **queen** [boss] — the one cell that plans: splits work into cards, assigns, reviews. Does not build.
  (Real queens lay eggs; ours dispatches. The word is for readability, not biology.)
- **worker** — a cell that claims paths, builds, ships. Same word in both kinds of hive.
- **desk** — the cell that talks to the keeper: relays asks, decides nothing keeper-only. Plain word, kept.
- **watchdog** — the bash loop that checks every cell every 5 s and respawns bodies. Plain word, kept.
- **card** — a ≤20-line task (Area / Owned paths / Done-when) handed to a worker. Plain word, kept.
- **comb** [board] — the append-only log every cell writes to: `.jiva/comb.log`; `jiva inbox` reads it.
- **claim** — a path a cell owns while editing (`.jiva/claims/<cell>`). **handoff** — ≤40 lines a body leaves
  for its successor. **gate** — one shell line proposed for the keeper to run. Plain words, kept.

Renamed with the words: `JIVA_BOSS_MODEL` → `JIVA_QUEEN_MODEL`, `just fleet` → `just hive`, the Kit's `.fleet/` →
`.hive/`, `.jiva/board.log` → `.jiva/comb.log` (move the file once; nothing else in `.jiva/` changes).
