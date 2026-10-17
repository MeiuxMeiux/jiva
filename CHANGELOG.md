# Changelog

All notable changes to this project are documented here.
The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and the project
aims to follow [Semantic Versioning](https://semver.org/spec/v2.0.0.html) once it leaves alpha.

## [Unreleased]

## [0.1.0] - 2026-10-17

First public alpha.

### Added

- **Fleet profiles** — `jiva up [solo|duo[:N]|full[:N]]`, picked from host size and quota when omitted
  (`just profile` explains the choice); optional loop seat for repos with live production.
- **Lean seats** — `--strict-mcp-config` plus a short `--disallowedTools` list by default (about half the boot context).
- **Gate rows** — `just gate-add|gate-run|gate-fix|gate-result`: one runnable line per human step, linted for a
  hard OK/MISSING gate; only the human runs them. `just desk-digest` prints nothing when nothing changed.
- **Cards and router** — cards need Area, Owned paths and Done-when; `docs/agents/AREAS.md` and `RULES.md`.
- **npx installer** — `npx jiva-fleet init|micro|doctor`: checks dependencies, clones JIVA, writes `JIVA.md`.
- **Avatar packs** — 28 packs (anime, comic book, old masters, halloween, robots and more), rotating on the site.
- **Preflight** — `jiva init`/`up` list exactly which tools are missing; model aliases with a per-user
  `~/.config/jiva/env` override.
- **Runtime spine** — bash + just: launcher, per-repo private tmux server (`tmux -L jiva-<repo>`),
  watchdog as window 0, desk/boss/worker roles, boot payload and statusline hooks.
  `jiva up|down|spawn|respawn|status`; workers soft cap 6, hard cap 12.
- **Portability** — `bin/jiva` works from any repo; code comes from the checkout, state goes in
  that repo's `.jiva/`. `jiva init` makes a repo fleet-ready.
- **Verbs** — `claim`, `unclaim`, `report`, `ask`, `ship`, `handoff`, `inbox`, plus desk-only
  `answer` and `pending`, over one append-only board.
- **Typed asks** — open/answered lifecycle, classes (decision/permission/deploy/spend), batched
  desk digest; only decisions expire to their default. Opt-in permission relay.
- **Self-heal and breakers** — dead-pane heal, context rotation before 200k tokens, repeat/storm/
  ceiling, burn/time/usd and heal-storm breakers, parking + `just unpark`.
- **Boss lease** — never two bosses, never zero.
- **Governor** — `jiva pause|resume|governor`, fleet $ cap, auth/usage-limit flag.
- **Guard hook** — PreToolUse git safety; STOP honored in every hook; `packs/local` guard.
- **Dashboard** — tier-1 on `127.0.0.1:<random port>` (sticky): flags, asks, lease, alerts,
  board, commits, history panels; strict CSP. Tier-2 phone view over a sanitized snapshot.
- **`jiva watch`** — live terminal view: bar, open asks, last board lines.
- **Notify** — portable toast, `notify.log`, optional ntfy backend.
- **History** — append-only `.jiva/history.jsonl` with emitters across verbs, asks and watchdog.
- **Souls** — roster packs (`jiva roster`), semi-persistent slot binding, affinity `jiva pick`,
  12 default-pack portraits.
- **Claude Code plugin** — local `jiva@jiva-local` plugin: hook wrappers, role skills,
  `/jiva-inbox`; hooks mode `plugin|settings`.
- **Budgets as tests** — `just check` (file/notes size, parse, JSON, shellcheck, README drift)
  and `jiva doctor` suites (payload, breakers, asks, perm, lease, plugin, watch, fault, `live`
  kill -9 self-heal). `jiva spike` re-tests version-sensitive assumptions.
- **Growth** — `jiva mine` ranks repeated commands from transcripts as recipe candidates.
- **Site** — static page with recorded hero, generated reference, SRI, CSP parity,
  a11y and drift checks, read-only `site-verify`.
- **Docs** — README, `docs/QUICKSTART.md` (verified on a fresh clone), `notes/` per area.
- **Security** — gitleaks pre-commit hook and `just sec` full-history scan.
- **Project docs** — `SUPPORT.md`, `.github/CODEOWNERS`, issue templates, README badges and contact,
  `packs/README.md` (portrait provenance and licence), a Permissions and Models step in QUICKSTART.
- **JIVA Micro** — `docs/MICRO.md`, a one-file paste-in fleet guide.

### Changed

- Public contact is <jiva@meiuxmeiux.com> in `SECURITY.md`, `CODE_OF_CONDUCT.md` and README.
- The original design brief and architecture plan moved to `docs/history/`.

[Unreleased]: https://github.com/MeiuxMeiux/jiva/compare/v0.1.0...HEAD
[0.1.0]: https://github.com/MeiuxMeiux/jiva/releases/tag/v0.1.0
