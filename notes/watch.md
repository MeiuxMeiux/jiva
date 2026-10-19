# watch — live terminal view (`jiva watch`, core/watch.sh)
Layout, top→bottom, redrawn every ${JIVA_WATCH_EVERY:-2}s (frame built in one var, printed once, alt screen):
- line 1 = `core/status.sh` line 1 + `q5h N% · q7d N%` from state.json; goes red AND gets `!! WORDS`
  (LEASE-STALE / RUNTIME-DOWN / PROTECTED-ASK / QUOTA≥85%) — never colour-only. NO_COLOR or no tput → plain.
- session rows: name · status · tok · pct · waiting (state.json `.sessions`).
- `FLAGS: a b  (clear: rm .jiva/flags/<name>)` only if a flag file exists.
- OPEN ASKS block only if open.jsonl non-empty; protected classes marked `[!]` (class list mirrors
  ASK_PROTECTED in core/asks.sh — keep both in sync).
- last N comb.log lines, N = terminal rows − used − 1, min 5. In a tty every line is clipped to `tput cols`
  in bash (char-aware); `tput rmam` is ignored by tmux, so wrapping would push the header off.
Keys: `q` quit · `a` prompt `<id> [text]` → `jiva answer` · any other key redraws now.
Piped / non-tty stdout: prints ONE frame (no escapes, no footer) and exits 0 — scriptable; rows from $LINES (def 40).
Test: `jiva doctor watch` (core/doctor-watch.sh, scratch TARGET + stub tmux on PATH, 30 checks).
- Rows end `· Nm ago verb text` (last comb line for that name; age from HH:MM, wraps at midnight) or `(no report yet)`;
  `quiet` when state tok − nudged/<name>.last tok > JIVA_QUIET (40k, below the 60k burn nudge). Rows clipped to COLUMNS.
- `ALERTS: Nm ago text · …` = last 3 notify.log lines newest first (notes/notify.md), hidden when no log;
  line 1 gets `!! … ALERT` while the newest is < 5 min old.
- Dash: `status.sh dash` → `dash http://127.0.0.1:<port>/` (pid alive) or `dash: down (jiva dash start)`; status line 1 + watch line 1 end with it (bar untouched).
