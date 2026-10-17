# Security

## Supported versions

JIVA is alpha. Only `main` gets fixes; there are no maintained release branches.

| version | supported |
|---|---|
| `main` (0.1.x alpha) | yes |
| anything older | no |

## Reporting a vulnerability

Report privately, either way works:

- GitHub private vulnerability reporting (preferred):
  <https://github.com/MeiuxMeiux/jiva/security/advisories/new>
- Email: <jiva@meiuxmeiux.com> (put "security" in the subject).

Please do not open a public issue for a security problem. Include what you ran, what happened,
and the smallest repro you have (`jiva` / `just` command, Claude Code version, `tmux -V`).

## Scope

In scope:

- **Hooks and the guard** (`core/` hook scripts, the PreToolUse git-safety guard, perm relay):
  bypasses that let a session push, force, or touch paths it did not claim; injection through
  board lines, asks or task cards.
- **Dashboard** (`jiva dash`): it binds to `127.0.0.1` only. Anything reachable off-host, path
  traversal, or data outside the snapshot allowlist leaking through it.
- **The site** (<https://jiva.meiuxmeiux.com>): header/CSP regressions, injected third-party content.
- Secrets reaching git, logs, the board or the dashboard.

Out of scope: what Claude Code itself does inside a session you started, and anything that needs
an attacker who already has your local user account.

## What to expect

Best effort, one maintainer. Expect an acknowledgement within about a week, a fix or a
plan when there is one, and credit in the advisory unless you ask otherwise.
