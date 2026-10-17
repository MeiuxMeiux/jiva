---
description: Desk (human) verb sheet — fleet lifecycle and setup verbs no session runs on its own
---
Desk verbs (run from the target repo; `jiva help` is the source of truth):

| verb | when |
|---|---|
| `jiva init` | once per repo: .jiva/, .gitignore, CLAUDE.md pointer |
| `jiva up [profile]` | start watchdog + seats: solo \| duo[:N] \| full[:N] \| N (auto; prints why) |
| `jiva down` | stop this target's fleet + dash |
| `jiva spawn <role> <name>` | add one session by hand |
| `jiva roster [gen\|check\|show]` | name/color/avatar packs |
| `jiva plugin [install\|status\|mode]` | user-scope plugin; mode = hooks source |
| `jiva spike` | re-test version-sensitive assumptions |
| `jiva mine [n]` | rank repeated Bash → recipe candidates |
| `jiva watch` | one live terminal view: bar + asks + board tail |
| `jiva pause [reason]` / `jiva resume` / `jiva governor` | hold the fleet (no heal/spawn/rotation) / lift it / show it |
| `jiva pending` / `jiva answer` | list / resolve asks escalated to the desk |

Show the user this table, then run `jiva status` and summarize it in one line.
