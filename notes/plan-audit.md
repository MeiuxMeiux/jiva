Maintainer log.
# plan-audit — docs/history/PLAN.md + KICKOFF.md vs HEAD 41ca3af (w1, 2026-10-13)
Done: ~40 promises verified (sha/file). Parked, out of table: 4 (parent-dir, npm+Go, publishing, deploy user).
In flight, not listed: history.jsonl (w2), commits modal + sticky dash port (w4), ntfy + dash URL (w3).

| doc section | item | status | proposed atom (claims) |
|---|---|---|---|
| PLAN Loops | `.jiva/STOP` obeyed by every hook | partial: watchdog + perm-relay only | lib.sh `stopped()`; guard denies all, session-start says STOPPED, statusline/breaker/affinity no-op; doctor (core/lib.sh core/hooks/ core/doctor-breakers.sh) |
| PLAN Loops | quota governor | partial: spawn/respawn refused + flags/quota ≥85; no pause/resume, no hive $ cap | core/governor.sh `jiva pause/resume` (.jiva/paused: no heal/lease spawn, handoff-say at ≥95), status shows PAUSED, hive usd cap (core/governor.sh core/status.sh core/doctor-fault.sh; jiva.sh at 149 → dispatch line only) |
| PLAN Dashboard/flag | flag on auth / usage-limit error | missing | breakers.sh greps capture-pane tail (usage limit, /login, API Error) → flags/<n>-auth + toast once (core/breakers.sh core/doctor-fault.sh) |
| PLAN Rotation | desk rotates only when idle, returns with 3-line recap | missing: desk is outside the watchdog loop | session-start role=desk injects 3-line recap (last ship, open asks, flags); desk statusline nudges at ≥150k only when asks=0 (core/hooks/session-start.sh core/hooks/statusline.sh core/doctor-asks.sh) |
| PLAN Build order | budgets as tests, complete | partial: payload/handoff/card/kill-9/files/notes ok | core/doctor-budgets.sh: CLAUDE.md ≤8, caps 6/12 refuse, 150k (75%) nudge once, state.json diet (numbers/enums + names), `claude --version` ≥2.1.236 + spike-stale when version ≠ last spike, no keep-going Stop hook (core/doctor-budgets.sh core/doctor.sh) |
| PLAN Dashboard | tier-2 phone view | missing | core/snapshot.sh: jq-allowlisted state → .jiva/snap/state.json + static read-only phone.html (CSP, no writes); hosting/tailscale/push = keeper ask (core/snapshot.sh core/phone.html core/doctor-dash.sh) |
| PLAN Lean boot | every message has a ttl | partial: asks have deadlines; comb/say lines don't | `jiva say` + comb lines carry ts; inbox/watch hide past JIVA_MSG_TTL (core/verbs.sh core/doctor-asks.sh) |
| KICKOFF Scans | `just sec` = gitleaks + trivy fs | partial: gitleaks only | sec runs trivy fs when on PATH, WARN when absent (justfile) |
| KICKOFF Scans | deploy-verify: testssl, Observatory | partial: verify.sh = headers/status/weight/SRI | verify.sh adds testssl.sh + Observatory API when available; keeper runs post-deploy (site/scripts/verify.sh) |
| PLAN Asks | "allow for this run" scoped expiring rules, queen proposes | missing by design (notes/perms.md: no allow-hook) | keeper ask: ask class `rule` + .jiva/rules.tsv expiry ledger the watchdog reminds the keeper to revoke (core/asks.sh) |
| KICKOFF Order of work | art-models/gen/pick/post, server-audit | missing (site art is hand-written SVG) | low: scripts/art.sh with cache + ledger + $ budget; server-audit = keeper ask (scripts/art.sh site/site.just) |
