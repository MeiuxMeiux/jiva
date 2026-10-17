# doctor — budgets as tests
Run: `just doctor` (static, always safe) · `just doctor live` (needs `just up`; ~1 min).
Output: one `ok`/`FAIL` line per check; exit 1 on any FAIL.

Checks and what they guard:
- boot payload (boss, w1): session-start.sh additionalContext chars/4 ≤ 1500 tok — keeps cold boot cheap.
- handoffs ≤40 lines, task cards ≤20 — a fresh body must reread them in one glance.
- state.json ts ≤30s old when `tmux -L jiva` is up — watchdog alive; "runtime down" is not a fail.
- settings.json command paths exist + executable — a dead hook silently drops boot/statusline.
- live: spawns scratch worker w9, kill -9 its claude pid, waits ≤45s for a new pid in
  `claude agents --json` (watchdog dead-pane respawn), then kills window w9 + launch/state/claims files.
- fault (static too): five injected faults on a scratch socket (notes/breakers.md); skipped without tmux.
Fact: live relies on heal() dead-pane respawn (core/breakers.sh); heal-storm parks a name after 3 heals in 5 min.
- dogfood asserts: lease (f) P2 pane-inherited TARGET yields to PWD repo (JIVA_PANE_TARGET via settings env), P9 init line; fault trust P8.
- budgets (core/doctor-budgets.sh): CLAUDE.md ≤8 rule lines, caps 6/7c/13, nudge 1-per-life, state diet (strings ≤40,
  one line), claude ≥2.1.236; spike-stale is WARN only (green `jiva spike` writes .jiva/spike.version).
- ttl: board lines end `<TAB><epoch>` (lib.sh board_log); inbox/watch read via board_tail (JIVA_MSG_TTL, 6h).
- history: `</dev/null jiva handoff` exits 1 with no handoff file/rotate mark (empty = refused); piped handoff still saves.
