> Original design brief (historical; may be out of date).

# JIVA — architecture plan

> Reference for core runtime work. Website/art/deploy live in `docs/history/KICKOFF.md`.

## Goal
One terminal (the **desk**) is the only session the human touches. The desk launches a **boss**
in tmux; the boss orchestrates N **workers** (models via `JIVA_BOSS_MODEL` / `JIVA_WORKER_MODEL`). All decisions, permissions and `!` commands bubble
to the desk. Every session, desk included, reincarnates before ~200k tokens. JIVA builds itself (ouroboros).
Optimize for **minutes any agent spends blocked on the human**, not agent count — decision latency,
merge friction and quota are the real limits.

## Asks
- Workers talk only to the boss. Only typed asks reach the desk: permission, decision, `!` command, ship
  notice — each with options, a default and a deadline.
- Permissions: a `PermissionRequest` hook in each worker posts the ask and blocks on an answer file.
  Agent-to-agent messages never count as human consent; the desk's answer applied via the hook is the path.
- "Allow for this run" → a scoped, expiring rule (answer classes, not instances). The boss may propose
  rules; only the human grants. Destructive classes (force-push, sudo, deletes outside claims) never
  auto-promote.
- Desk status line shows the pending count at zero tokens; the desk wakes only for a batched digest.
- Hook timeout → fall back to the native prompt, and the dashboard flags it.

## Rotation
- Task-sized lives; ~200k is the emergency ceiling. Boot payload < ~1.5k tokens, so a fresh body is cheaper
  than a stale one.
- Status line writes context size to a state file. At ~85% the watchdog nudges: finish the current atom,
  write a handoff (≤40 lines of pointers into the board, not narrative).
- The **watchdog, never the agent**, kills and runs `tmux respawn-pane -k` into a fresh `claude`.
- Boss holds a lease: never two, never zero. Desk rotates only when idle (no pending ask, no typing) and
  returns with a three-line recap.
- Rotation-storm breaker parks any life that blows the ceiling right after boot.

## Lean boot, no worktrees
- `CLAUDE.md` ≈ 6 lines (run `just --list`; the six verbs). A `SessionStart` hook injects role + task from
  launcher env vars, so one repo serves desk, boss and workers.
- Boss delegates pointers: a ≤20-line task card (goal, done-check, paths to claim, read-list) plus area
  notes matched by longest path prefix.
- Six verbs as `just j-*` recipes: `inbox`, `claim`, `report`, `ask`, `ship`, `handoff`.
  - `report done` runs `just check` itself, so "done" is verified.
  - `ship` commits only claimed paths and pushes under `flock`; a hook denies `git add -A`, `stash`, `checkout`.
- Directory-level claims at assignment time replace worktrees (keep one worktree as an escape hatch).
- Justfile growth: a non-LLM script mines `~/.claude/projects` transcripts, ranks repeated Bash sequences
  by frequency × output size × retry rate, and hands the model only the top ten to turn into recipes.

## Loops (every defense is non-LLM)
- Nothing polls: agents end their turn and get woken. Workers never talk to each other; every message has a ttl.
- Breakers: identical repeated tool calls; tokens burned with no commit/report; per-life token/time/$
  ceilings; rotation storms.
- Global governor stops spawning as quota tightens (status line exposes 5h/weekly usage on Pro/Max;
  track dollars on an API key).
- `.jiva/STOP` is the kill switch every hook obeys.
- Cap known loop engines by name: `/loop`, `/goal`, and any Stop hook that tells the agent to keep going.

## Souls and affinity
- Names, colors, avatars are launcher-assigned labels, never prompt personality. `--name` and `/color`
  surface natively in agent view and @-mentions.
- "Same soul, same area": a `PostToolUse` hook appends edit paths to a tiny table
  (soul × depth-2 path × decayed count); `jiva pick <paths>` returns the best idle soul. Nobody scans history.
- Caveat: bodies are fresh, so affinity buys no capability. **Area notes do** — each worker appends one durable
  fact to `notes/<area>.md` (≤~30 lines). Build notes first; affinity is a free tiebreaker.

## Roster
- Pack format: slot → `{name, color, avatar}`. 24 slots, 12 with art, fallback silhouette beyond.
- Private test art only in gitignored `packs/local/` from commit one (scrubbing history later = rewrite).
  Ship generated avatars and original names by default.
- Soft cap 6, hard cap 12 behind a confirm (docs suggest 3–5 teammates; 10 agents ≈ 10× quota burn).

## Dashboard and the can't-bubble flag
- Watchdog merges `claude agents --json`, status-line writes, hook events and tmux pane uptimes into one
  `state.json` of **numbers and enums only** (no prompts, paths or branch names).
- Tier 0: tmux status bar, e.g. `5 live · 1 flag · 412k` — free, in the one terminal.
- Tier 1: local page on a random high port (WSL2 forwards localhost to the Windows browser).
- Tier 2 (phone): `tailscale serve`, or outbound-only push of the sanitized snapshot to a static host behind
  an unguessable URL. No inbound port; read-only by construction. Uncommon port = obscurity, not security;
  real protection is localhost binding, outbound-only, the data diet, capability-token URL, strict CSP,
  no write endpoints.
- Shows: session count, current tokens per session (last watchdog), per-session total, cumulative total,
  uptime per session, attention flag.
- Flag fires when worker → boss → desk is broken:
  - stale heartbeat (page greys out when `state.json` > ~30s old — its own dead-man's switch)
  - a session stuck at a permission prompt (`claude agents --json` reports `waitingFor`)
  - expired boss lease, quota nearly gone, auth/usage-limit error, tripped breaker
  - tmux or watchdog down
- Out-of-band ping so the flag doesn't depend on looking: Windows toast via `powershell.exe`, or ntfy.

## Distribution (three layers)
1. **npx as courier** for `init`, `up`, `doctor` — never the runtime. Hooks can't use npx (cold start per
   tool call); they POST to the local daemon or run a tiny shell script. Core in **Go** (≤150-line files;
   JIVA lints itself with that rule), shipped esbuild-style: small npm shim + per-platform binaries.
2. **Claude Code plugin** in a marketplace on GitHub: hooks, status line, role skills installed once
   at user scope. Each repo's footprint shrinks to a justfile + the six-line pointer.
3. (Dropped: an npx installer. JIVA installs from git.)

- `jiva up` starts a dedicated tmux server (`tmux -L jiva`) so it never touches the user's sessions. The
  terminal is a client on it; desk is pane 0.
- Parent-directory mode: `.jiva/` lives at the parent; claims are prefixed by repo.
- File bus is the baseline; native messaging is an accelerator (cross-machine needs a claude.ai login).

## Core spike (half day, pass/fail)
1. Two tmux-launched sessions see and message each other; idle subscription fires
   (version floors: v2.1.224, v2.1.236).
2. `claude agents --json` reports `waitingFor` for a tmux session stuck at a prompt.
3. A `PermissionRequest` hook blocks on an answer file, returns allow/deny, falls back cleanly on timeout.
4. Status-line numbers → state file → `respawn-pane -k` → fresh session picks up a handoff via `SessionStart`.
5. tmux server survives closing Windows Terminal. WSL may idle-shut-down and take it along; a keepalive fixes it.

## Build order (after the spike passes)
Hand-roll a ~150-line bash + just spine (desk, boss, two workers), then let JIVA build itself.
State as of 2026-10-13 (sha = `git log --oneline`):
- [done] spike — 956bff3 (checks 1, 2, 4 pass), d452b64 (`jiva spike` re-test)
- [done] spine: launcher, watchdog, boot/statusline hooks, role cards — c0022b6
- [done] bus: six verbs over the file bus — c56e08d; portability (any repo, per-target socket) — efc57d4
- [done] hooks & state: guard hook, state.json — 0ddc3e6, c0022b6
- [done] rotation: nudge at ~85%, handoff, watchdog respawn, dead-pane self-heal — c0022b6, 358f4af
- [done] asks: typed asks, `jiva answer`, batched digest — c56e08d, ef7d64f
- [done] breakers: repeat/storm/ceiling, burn/time/usd — 358f4af, f5ab4b7
- [done] status bar & dashboard — c0022b6, 7281457
- [done] budgets as tests (`jiva doctor`) — 39eadc1, d452b64
- [done] justfile mining (`jiva mine`) — 0ddc3e6
- [done] roster + affinity (`jiva roster`, `jiva pick`) — b298434, ba81ffe
- [done] packaging, plugin layer — b89da0f, ebfa391 (installing into ~/.claude is the human's step)
- [dropped] packaging, npm shim + Go core — bash stays the runtime
- [done ca8c902] boss lease (never two, never zero) — core/lease.sh, watchdog lease_tick, jiva doctor lease
- [parked] parent-directory mode (`.jiva/` at the parent, repo-prefixed claims) — 2026-10-13: one repo per fleet covers the use case

**Budgets are tests:** `jiva doctor` fails if a boot payload tops ~1.5k tokens, a handoff tops 40 lines, or
`kill -9` on any pane doesn't self-heal. Keep everything version-sensitive behind one adapter and rerun the
spike after every Claude Code update (agent view and channels are research previews).

## Defaults (flip any)
Go core + npm shim · tmux as the body behind a swappable adapter · file bus first, native messaging as accelerator.
