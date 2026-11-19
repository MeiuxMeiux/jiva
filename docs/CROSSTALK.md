# JIVA Crosstalk: Claude Code sessions talking to each other, across servers, via `just`

Paste this file into a repo as `CROSSTALK.md`, open Claude Code there and say:
**"Read CROSSTALK.md and set up crosstalk on this box. Show me each file before you write it."**
Nothing to install beyond what an agent box already has: bash, tmux, ssh, and `just` (https://just.systems).
Part of JIVA (https://github.com/MeiuxMeiux/jiva), but it needs none of it. Plain text: read it before you hand it over.

## The idea in five lines
1. A Claude Code session in tmux has a pane. Typing into the pane is a message; reading the screen is a peek.
2. On one machine, Claude Code's own peer messaging (ListAgents / SendMessage) works between sessions. It stops at the
   machine's edge, and some sessions (older builds, a phone over ssh, a cron) can't use it.
3. Across machines you already have ssh. Wrap the far box's recipes in one recipe on your hub:
   `just ernie say gw-boss "ship it"` runs `just xt say …` on ernie.
4. The way back is a file. Far agents append to an **outbox**; the hub follows it with `tail -F`: zero tokens until
   something arrives.
5. `just` is the contract. Agents learn five verbs from `just --list`, not tmux flags. The guard (never type into a
   permission prompt) lives in the recipe, and the output is the few lines the recipe chose to print.

```
 hub (your desk session)                          box "ernie"
 just ernie say desk "…"  ── ssh ──▶  just xt say desk "…"  ──▶ tmux pane "desk"
 just ernie peek desk     ── ssh ──▶  just xt peek desk     ◀── screen text
 monitor: ssh ernie tail -F outbox ◀──── just xt post "subject" "body" (any agent there)
```

## Step 1: on every box that runs agents, `crosstalk.just` next to the justfile
Then add `mod xt 'crosstalk.just'` to that justfile (just ≥1.31). `just xt` lists the verbs.
```just
# Crosstalk: talk to the Claude Code sessions in tmux on this box. `just xt` lists these.
set positional-arguments
set shell := ["bash", "-c"]
me := env('XT_NAME', `[ -n "${TMUX:-}" ] && echo "$(tmux display -p '#S')@$(hostname -s)" || hostname -s`)
outbox := env('XT_OUTBOX', env('HOME') / '.crosstalk/outbox.md')
prompt := 'Do you want|❯ 1\. Yes|Enter to confirm'

default:
    @just --justfile '{{source_file()}}' --list

# every tmux session: name, busy | idle | PROMPT, working dir
agents:
    #!/usr/bin/env bash
    for s in $(tmux ls -F '#{session_name}' 2>/dev/null); do
      t=$(tmux capture-pane -p -t "=$s:" | grep -v '^\s*$' | tail -15); st=idle
      grep -q 'esc to interrupt' <<<"$t" && st=busy
      grep -qE '{{prompt}}' <<<"$t" && st=PROMPT
      printf '%-16s %-7s %s\n' "$s" "$st" "$(tmux display -p -t "=$s:" '#{pane_current_path}')"
    done

# last n non-blank lines of a session's screen
peek name n="30":
    @tmux capture-pane -p -t "=$1:" -S -200 | grep -v '^\s*$' | tail -n "$2"

# type a stamped message into a session and press Enter; refuses at a permission prompt (Enter would answer it)
say name +text:
    #!/usr/bin/env bash
    set -euo pipefail
    n=$1; shift
    tmux capture-pane -p -t "=$n:" | grep -v '^\s*$' | tail -15 | grep -E '{{prompt}}' >/dev/null && { echo "$n is at a prompt: peek it, answer by hand"; exit 1; }
    tmux send-keys -t "=$n:" C-u; sleep 0.3
    tmux send-keys -t "=$n:" -l "[$(date -u +%H:%MZ) from {{me}}] $*"; sleep 0.3
    tmux send-keys -t "=$n:" Enter
    echo "said to $n"

# leave a message for whoever watches this box (the hub): appends one block to the outbox
post subject +body:
    #!/usr/bin/env bash
    set -euo pipefail
    mkdir -p "$(dirname '{{outbox}}')"; s=$1; shift
    printf '## %s %s: %s\n%s\n' "$(date -u +%H:%MZ)" '{{me}}' "$s" "$*" >> '{{outbox}}'
    echo "posted to {{outbox}}"

# the last n lines of the outbox
outbox n="40":
    @touch '{{outbox}}'; tail -n "$1" '{{outbox}}'
```

## Step 2: on the hub (the machine your desk session runs on), one recipe per box
```just
# agents on ernie: just ernie agents | peek <s> | say <s> "<text>" | post | outbox
[positional-arguments]
ernie *args:
    @ssh -o BatchMode=yes -o ConnectTimeout=10 root@ernie.example "cd /srv/desk && XT_NAME=hub-desk just xt $(printf '%q ' "$@")"
```
`[positional-arguments]` + `printf '%q '` keep `"two words"` as one argument through ssh; `XT_NAME` signs your messages. The hub needs bash as its
just shell (`set shell := ["bash", "-uc"]`). A hub can itself be a box: hubs and boxes are roles, not machines.

**The way back, zero tokens.** The hub session starts one background watcher per box and gets a turn only when a
line lands: `ssh -o ServerAliveInterval=30 root@ernie.example 'tail -n0 -F ~/.crosstalk/outbox.md'`. In Claude Code
that is the Monitor tool (or a `run_in_background` Bash); outside it, any terminal. No watcher? `just ernie outbox`
at the start of each turn.

## Step 3: tell the agents (paste into each box's CLAUDE.md, fill in the desk line)
```
## Crosstalk (just xt)
- The desk is <session name> on <machine>. It reaches you by typing into your pane; you reach it with
  `just xt post "<subject>" "<≤10 lines>"`. Never edit the outbox file: post appends.
- Same box: `just xt agents` (busy/idle/PROMPT), `just xt peek <s>`, `just xt say <s> "<msg>"`
  (or SendMessage if you have it). Messages arrive as "[HH:MMZ from <name>] …".
- One reply per message, then back to work. No thank-you or acknowledgement-only messages.
```

## Test it in two minutes (no tokens)
```
tmux new -d -s xt-test cat              # a fake "agent" that just echoes
just xt say xt-test "hello there"; just xt peek xt-test 3    # shows: [14:02Z from …] hello there
just xt post "test" "it works"; just xt outbox 2
tmux kill-session -t xt-test
```
From the hub: `just ernie agents`, then `just ernie say <session> "reply with just xt post"`, and watch it arrive.

## Rules that came from real incidents
- **Never type into a prompt.** Enter answers "Do you want to run…?". `say` refuses; `agents` shows PROMPT.
- **Clear, type, pause, Enter.** `C-u` first, or your text glues onto a half-typed draft. `-l` sends text literally
  (a message containing "Enter" stays text). The 0.3 s pauses stop a long message being submitted half-pasted.
- **A busy session is fine.** Claude Code queues what you type and reads it when its turn ends.
- **Append, never rewrite.** An agent that "edits" the outbox replaces the file, and a `tail -F` watcher
  then replays everything ("file replaced; following new file"). `post` uses `>>`.
- **Quote across ssh with `printf %q`; ship content with scp.** A heredoc inside `ssh '…'` once ran its backticks
  on the far box. Longer asks: write the file locally, `scp` it into an inbox dir, `say` its path.
- **Stamp every message** with time and sender, so a session that reads it an hour later knows its age and whom to answer.
- **Write down who the desk is.** Two agents once spent turns asking each other who the desk was, because the old
  desk had died. One line in each CLAUDE.md fixes it; update it when the desk moves.
- **Watch with a loop, not a model.** A watcher that prints only on change costs nothing; an agent that peeks every
  turn spends its context reading screens.
- **The hub can be off.** A laptop sleeps. Far agents keep going on their own rules; the outbox waits.
- **ssh is the security boundary.** Anyone who can run `just ernie say` can drive those agents. Key-only ssh,
  no crosstalk recipe that takes a host name from its arguments, and the far box's agents keep their own permission rules.

## No `just` yet?
Install it (https://just.systems/man/en/packages.html), put an empty `justfile` in the repo, and add one line to
CLAUDE.md: **"Run `just --list` first and prefer recipes over ad-hoc shell; when you run the same command twice,
add a recipe that prints only what matters."** Agents then build the recipes for you, and every repeat costs a line
of output instead of a screenful.
