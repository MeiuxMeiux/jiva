# fleet — seats, sizing, lean launch, gate rows, desk digest (lane A, 2026-10-17; claude 2.1.302)
Seats: desk (human terminal, core/roles/desk.md) · boss · loop (opt-in, core/roles/loop.md) · wN · watchdog (bash, 0 tok).
- Profiles (core/profile.sh, `just profile [p]` dry-run, `jiva up [p]`): solo = watchdog + w1, no boss (desk is boss);
  duo[:N] = boss + N (default 2; a bare N = duo:N); full[:N] = boss + loop + N. Empty = auto: solo if quota ≥70%
  (JIVA_SOLO_QUOTA) or host fits <3 seats (avail MB − 1024)/JIVA_SEAT_MB 700, else duo:min(JIVA_WORKERS 2, fit−1).
  Full is never auto. Prints the why lines. `.jiva/profile` = the name; solo → lease_tick never spawns a boss and
- A fresh `up` (no tmux server yet) clears .jiva/launch + claims: heal respawns every launch file, so a stale
  launch set once resurrected an old boss + w2–w4 with finished cards into a solo fleet.
  session-start tells seats "Boss session: desk".
- Lean launch (jiva.sh lean()): every seat gets `--strict-mcp-config --disallowedTools Artifact,ArtifactComments,
  ArtifactData,NotebookEdit` (JIVA_LEAN_DENY overrides, JIVA_LEAN=0 opts out). Strict + no --mcp-config = zero MCP
  servers (claude.ai connectors too). Shop measured 56k→24k boot; not re-measured here.
- Context: watchdog nudge at 75% of CEIL = 150k (JIVA_NUDGE), loop seat 100k (JIVA_LOOP_NUDGE); breakers toast an
  alert at 185k (JIVA_ALERT, notify.log = the alerts log); 200k = hard-ceiling say. Handoff → idle → respawn (unchanged).
- Gate rows (core/gate.sh; `just gate-add|gate-fix|gate-run|gate-result`): .jiva/gate/rows.jsonl, kind oneliner only.
  Lint at add: one line, a NAME-OK/MISSING/FAIL word + `exit N`/`false` at the end, no uppercase $VAR inside a
  single-quoted sed/awk program ($NF/$NR ok). `go` refuses when JIVA_ROLE is set (fleet seat); validates the whole
  batch first, deps must be ok, stops at first fail; <id>.out/.rc saved; the asker gets a say. fix = new row + <old>.sup.
- Desk digest (core/digest.sh, `just desk-digest`): snapshot in .jiva/digest.last of pushed(@{u}) / asks / gate / newest
  alert / parked / flags; prints only changed items, nothing when quiet. `digest.sh reset` re-baselines.
- Cards: core/card.sh (`just card`) needs Area:, Owned paths: (or Claim:), Done-when: (or Done-check:). `jiva assign`
  itself still only size-checks (QUICKSTART's Claim-only cards keep working).
- New `jiva` subcommands FAIL readme-drift (README is not lane A's) — new surface goes in core/fleet.just recipes.
- Tests: `jiva doctor fleet` (core/doctor-fleet.sh, scratch /tmp/jiva-scratch/doctor-fleet; static doctor runs it).
- Areas → paths → the ONE note: docs/agents/AREAS.md · rules with incident reasons: docs/agents/RULES.md.
