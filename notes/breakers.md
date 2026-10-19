# breakers — breakers, flags, parked, guard (split from notes/core.md 2026-10-13)

- guard.sh (PreToolUse Bash|Skill): only segments *starting* with git/claude count (split ;&|); Skill loop|goal denied.
- Breakers write `.jiva/flags/<name>` (repeat|storm|ceiling|burn|time|usd|heal-storm); state.json `flags` counts
  them; desk clears with rm; `.jiva/parked/<name>` blocks respawns. Self-heal skips a tick if `claude agents` fails.
- `perm-timeout` is a flag file too (from perm-relay, notes/perms.md): counted, cleared with rm like the rest.
- Queen lease (core/lease.sh): `.jiva/lease/queen` = `<epoch> <sid> <pane>`, refreshed by the queen statusline
  (`refreshInterval: 30` so an idle queen still ticks). Refused only if fresh (<JIVA_LEASE_TTL 90s), other sid
  AND other pane — respawn-pane keeps the pane id, so a respawned queen takes over. Pane is `-` off our socket.
- Watchdog lease_tick: kills `lease/extra.<pane>` + stray queen-window panes; no queen window → spawn (30s
  grace after watchdog start, skips parked); >3×TTL → flags/lease-stale. `jiva doctor lease` (JIVA_DRY=1).
- Dash panels: dash.sh serves read-only /flags /asks /lease (stdlib python, per-GET; protected = asks.sh ASK_PROTECTED);
  banner red on flags, lease stale or any protected ask. `jiva doctor dash` (scratch TARGET + JIVA_DASH_PORT).
- heal-storm: heal_ok counts respawns in `.jiva/heals/<name>`; ≥3 in 5 min → parked + flag + toast (count reset on park).
- Faults (`jiva doctor fault`, scratch socket, stub claude): watchdog kill -9 → nobody restarts it; status
  "watchdog dead" + red status-right (`status.sh bar`, set by wd_bar) at >30s → `just restart-watchdog`.
  state.json bad → status/bar say "unreadable", tick rewrites it. Disk full → one flags/disk-full (0-byte ok).
  tmux dead → status "runtime down", no lease claim; `jiva up` recovers. q5h/q7d ≥85 → flags/quota; spawn refuses.
- Governor (core/governor.sh pause|resume|status): `.jiva/paused` → no heal/lease_tick/rotation, one "handoff now" ≥95%;
  JIVA_FLEET_USD cap auto-pauses once (flags/hive-usd). Auth: pane tail "limit reached|run /login|API Error: N" → flags/<n>-auth.
