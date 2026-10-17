# QUICKSTART — a JIVA fleet on a second repo

> verified 2026-10-13 against 9561a4c (notes/dogfood.md): the sequence below, steps 1-7, ran clean
> end to end on a fresh clone. Every `jiva …` / `just …` below is drift-tested by `just check`.

## 0. Prerequisites (once per machine)

Linux or WSL2. bash ≥4, git, tmux ≥3.2, jq ≥1.6, just, python3, util-linux (flock, setsid), coreutils, Claude Code. Optional: gh, shellcheck, gitleaks.
macOS: untested (needs Homebrew bash, coreutils, util-linux).

Then the checkout on PATH:

```
git clone https://github.com/MeiuxMeiux/jiva ~/jiva   # or: gh repo clone MeiuxMeiux/jiva ~/jiva
export PATH="$HOME/jiva/bin:$PATH"
jiva help                     # the verbs; `jiva help` is the truth, not this page
jiva plugin status            # exit 0 = plugin installed (hooks come from it); otherwise --settings
```

Hooks reach each pane either through a `--settings` file (default) or the optional local plugin.
Installing the plugin writes to ~/.claude, so it is a step you run yourself: `jiva plugin install`.

**Permissions.** Every seat is a Claude Code session in a hidden tmux pane. A permission prompt there
stalls that session until someone answers it in the pane; `jiva pending` lists who is waiting and where.
JIVA never edits permission settings for you, so allow the routine commands up front. Commands that do
not match still prompt as usual: that is the safety net, not a bug.

- **Mode:** Claude Code's `auto` permission mode is recommended (most routine calls never prompt).
  It is not required: `acceptEdits` plus the allowlist below also works, with more prompts.
  Never use `--dangerously-skip-permissions` for a fleet.
- **Allowlist:** in the target repo's `.claude/settings.json` (project level; or in `~/.claude/settings.json`
  for every repo). Sessions commit by explicit pathspec, and `jiva ship` pushes under a lock:

```
{
  "permissions": {
    "defaultMode": "auto",
    "allow": [
      "Bash(jiva:*)", "Bash(just:*)", "Bash(jq:*)", "Bash(tmux:*)",
      "Bash(git status:*)", "Bash(git diff:*)", "Bash(git log:*)", "Bash(git show:*)",
      "Bash(git add:*)", "Bash(git commit:*)", "Bash(git push:*)",
      "Bash(ls:*)", "Bash(cat:*)", "Bash(grep:*)", "Bash(head:*)", "Bash(wc:*)", "Bash(sed -n:*)"
    ]
  }
}
```

Add your project's own build and test commands. Whatever the allowlist says, JIVA's guard hook still
denies `git add -A`, `git stash`, branch switches, `reset --hard` and force pushes.

**Models.** The boss runs `JIVA_BOSS_MODEL`, workers `JIVA_WORKER_MODEL`; both default to the `opus`
alias. Override per run (`JIVA_WORKER_MODEL=sonnet jiva up 2`) or once per user with `KEY=VALUE` lines
in `${XDG_CONFIG_HOME:-$HOME/.config}/jiva/env` (`JIVA_*` keys only).

## 1. Make the repo fleet-ready

Use a plain shell: no `JIVA_*` / `CLAUDE_*` inherited from another fleet's pane (an inherited
`JIVA_TARGET` beats `$PWD`'s repo). Any git repo with a pushable `origin` works:

```
cd ~/code/myrepo              # JIVA's code still runs from ~/jiva
jiva init
git add .gitignore CLAUDE.md && git commit -m "jiva init"   # init leaves both uncommitted
```

`init` creates `.jiva/` (runtime state: board, claims, tasks, handoffs, state.json), adds it to
`.gitignore`, and writes a 4-line `CLAUDE.md` pointer only if the repo has none. Each target gets its own
tmux socket, `jiva-<repo>` (here `jiva-myrepo`), so fleets on different repos never collide.

## 2. Start the fleet, trust the path once

```
jiva up 1                     # socket jiva-myrepo: windows watchdog, boss, w1
```

A repo path Claude Code has never seen stops every pane at its workspace-trust dialog. One
click per pane, once per path (trust persists; JIVA never auto-accepts it):

```
tmux -L jiva-myrepo attach -t jiva:boss   # ↓ Enter, Ctrl-b n, ↓ Enter, Ctrl-b d
```

The sessions boot themselves after the click; no re-run. Or pre-trust: run `claude` in the repo once
before `jiva up`. Workers: soft cap 6 (`JIVA_CONFIRM=1` above it), hard cap 12; each one burns
quota like a session of its own. `JIVA_DESK=<name>` names the desk the board lines credit.

## 3. Watch it

```
jiva status                   # one-line summary from .jiva/state.json; expect "2 live" (boss + w1)
jiva watch                    # live view: bar + open asks + last board lines
jiva dash start               # tier-1 dashboard on 127.0.0.1:<random port>; `jiva dash url` reprints it
jiva doctor                   # budgets as tests: boot payload, handoffs, hooks, state freshness
```

"0 live" right after `up` usually means a pane is still parked at the trust dialog (step 2).

## 4. Give a worker a task card

A card is ≤20 lines: the task, numbered steps, a done-check, and a `Claim:` line naming the paths.

```
cat > card.md <<'CARD'
## Task: add a --verbose flag to the CLI
1. Parse --verbose in src/cli.py; print each step when set.
2. Add a test in tests/test_cli.py.
Done-check: test suite green.
Claim: src/cli.py tests/test_cli.py
CARD
jiva pick src/cli.py          # best idle worker for these paths (advice; you or the boss choose)
jiva assign w1 card.md        # installs the card, respawns w1 with it, kicks it off
```

Usually the boss writes and assigns cards; `jiva say boss "<text>"` types a line into its pane.
The worker then runs the session verbs itself: `jiva claim`, `jiva report done`, `jiva ship`; the board
shows claim, done, ship and the commit lands on `origin`. About a minute after the trust click.

## 5. Answer what bubbles up

```
jiva inbox                    # last board lines + open asks
jiva answer <id> "<text>"     # close an ask (no text = its default)
jiva pending                  # sessions stuck at a native prompt, and where to answer them
```

A quiet fleet: `jiva pending` prints "(nothing waiting)" and `jiva doctor` is all ok.

## 6. Context rotation is automatic

The watchdog checks every session every 5 s. Before a session passes ~200k tokens it is told to
`jiva handoff` (≤40 lines of pointers) and is respawned fresh with it. To force one by hand:
`jiva respawn w1`. After editing core/watchdog.sh: `jiva restart-watchdog`.

## 7. Stop

```
jiva down                     # kills this repo's jiva tmux server + dash only
tmux -L jiva-myrepo ls        # "no server" = stopped
```

`.jiva/` stays (gitignored), so the next `jiva up` resumes from the board, cards and handoffs.

## Same thing via just (inside the jiva checkout)

`just up`, `just status`, `just fleet`, `just doctor`, `just down`; verb wrappers are `just j-*`
(`just j-inbox`, `just j-answer <id>`). `just --list` is the truth for recipes.
