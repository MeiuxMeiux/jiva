# JIVA Kit: one file, and the agent you already have sets up the fleet with you

Put this file in any git repo as `KIT.md`, open Claude Code there, and say:

**"Read KIT.md. You are my desk now. Start at Step 0 and stop after every step so we can look together."**

The agent reading this becomes the **desk**: the one seat you talk to. It installs the files at the bottom
of this page into `.fleet/`, then works through the steps *with* you: tidies the markdown your sessions boot
with, sets up `just`, mines your past conversations for recipes (and tells you what they would have saved),
and ends by telling you the fleet is ready and how to run it. It never deploys, pushes or launches seats:
those lines are handed to you to run. The why behind every step: JIVA Micro (`micro.md`, next to this file).
Full runner with watchdog, dashboard and verbs: https://github.com/MeiuxMeiux/jiva

Needs: Linux or WSL2, bash 4+, git, tmux 3.2+, jq, just, flock (util-linux), Claude Code.

## If you are the agent reading this
- You are the desk for the rest of this session. Work *with* the human: show, ask, then change. After each
  step print a short report and stop. Never run a line marked HUMAN; print it for them instead.
- Decisions go in front of the human as options, recommended first. Mundane choices you take yourself and say so.
- Every edit to the human's files is shown as a diff first. You never delete their notes: you move them.
- When a step cannot be done here (missing tool, denied permission), say what is missing and the one line that
  fixes it. Never route around a denial.

## Step 0: install the files (you, the agent)
1. Copy each block under **Files** to the path in its heading (`.fleet/<path>`; the `fleet.just` block →
   `.fleet/fleet.just`), then `chmod +x .fleet/bin/*.sh`.
2. Add `mod fleet '.fleet/fleet.just'` to the repo's `justfile` (create one if there is none). Every fleet
   recipe is then `just fleet <recipe>`; `just fleet` lists them.
3. `echo '.fleet/state/' >> .gitignore` (runtime state: claims, seat json, alerts, gate results).
4. Merge the keys of `.fleet/settings.json` (statusLine, permissions.allow) into `.claude/settings.json`.
5. Report: `just fleet` output, `tmux -V`, `jq --version`, `claude --version`, `git status --short`.

## Step 1: measure (read-only)
1. `nproc`, `free -m`: about 1 GB RAM and 1 core per seat. Fewer than 3 seats fit → solo mode (desk + 1 worker).
2. Quota: ask the human to run `/context` in a fresh session and paste it. Note the tokens taken by the
   system tools, MCP tools, memory files and the CLAUDE.md chain. Write them down: **before**.
3. Is anything here live in production? Only then is a loop seat worth it. Who else commits here?
4. Report before/after will come at the end of Step 2; for now the numbers and the seat count you recommend.

## Step 2: tidy the startup files, together (the biggest lever: every line costs every seat on every restart)
Startup files = whatever Claude Code loads before the first word: the root `CLAUDE.md`, `CLAUDE.md` in
subdirectories, `~/.claude/CLAUDE.md`, memory (`MEMORY.md` + memory files), rules, and MCP servers.
1. List them with line counts. Show the human what loads and roughly what it costs.
2. Root `CLAUDE.md` becomes a router of 40 lines or fewer, built from `.fleet/templates/CLAUDE.md`: a scope
   guard, one line per rule, pointers. Every paragraph that is detail moves to `notes/<area>.md` (30 lines or
   fewer each) or `docs/agents/*.md`, read on demand. Propose the split as a table (line → where it goes),
   get a yes, then do it. Never drop a rule the human wrote: move it and link it.
3. Subdirectory `CLAUDE.md`: one line per rule. Memory: `MEMORY.md` is an index, one line ≤140 characters
   per memory, one fact per file; a long index gets truncated and silently drops the newest lines.
4. MCP: seats launch with `--strict-mcp-config` unless their card needs a connector. List the servers and
   the ones a worker never needs.
5. Ask for `/context` again and show **before → after** per line item. One fleet measured 56k → 24k per seat.

## Step 3: `just` is the blessed path (mine the past for recipes)
Seats call recipes, never raw tmux or git: one place for guards and logs, and the output is what the recipe
chose to print, not a screenful.
1. `just fleet mine 15`: ranks the Bash commands your past sessions in this repo repeated (freq × output size ×
   retries) and ends with the estimate: tokens those repeats cost, and what recipes that print only what
   changed would have kept out of context. Show the table and the estimate.
2. Propose 3 to 6 recipes from the top rows: name, one-line comment, what it prints. Writes print what they
   did and exit non-zero on surprise; anything that sends (mail, chat, push) takes `--dry-run`.
3. Write the ones the human picks into the root `justfile`, run each once, show the output. Add the line
   "Run `just --list` first; prefer recipes over ad-hoc shell. A sequence done twice → propose a recipe." to
   `CLAUDE.md` if it is not there.

## Step 4: rules, roles and the first card
1. `.fleet/templates/rules.md` → `.fleet/rules.md`, linked from `CLAUDE.md`. Read it with the human: each
   line is a rule and the afternoon it cost somebody. Drop none, add theirs.
2. Role sheets are already in `.fleet/roles/` (desk, boss, worker, loop). Explain the shape in five lines:
   desk relays and decides nothing human-only; boss plans and writes cards, never builds; workers own paths
   and build; watch is a bash loop with no model. Solo mode: no boss, the desk writes the cards.
3. Write the first card with the human, from `.fleet/templates/card.md`, as `.fleet/cards/w1.md`: Area,
   Owned paths, Goal, Done-when, Read first. A card missing any of them is refused by `just fleet add`.

## Step 5: launch (HUMAN runs the lines; you print them)
```bash
just fleet up                              # private tmux server `tmux -L fleet` + zero-token watch window
just fleet add w1 .fleet/cards/w1.md       # seat w1 on its card (reads .fleet/roles/worker.md first)
```
First run in a repo, Claude Code shows a workspace-trust dialog once: `tmux -L fleet attach`, accept it, detach
(`Ctrl-b d`). Then confirm with `just fleet ls` and `just fleet peek w1`. When w1 shows live, say it plainly:

> **Your fleet is ready.** One worker on w1, watch running, claims and gates armed.

Then print the daily cheat sheet:
- `just fleet ls` seats + tokens · `just fleet peek w1 40` its screen · `just fleet say w1 "…"` talk to it
- `just fleet add w2 .fleet/cards/w2.md` another seat · `just fleet stop w2` done · `just fleet restart w1` wedged
- `just fleet claims` who owns what · `just fleet gate-list` lines waiting for you · `just fleet gate-run go <id>`
- `just fleet usage` quota · `just fleet digest` what changed · `just fleet down` all off (your tmux untouched)

## Step 6: rhythm (how the desk lives from now on)
- One Monitor on `just fleet digest` every 10 minutes: it prints nothing when nothing changed, so a quiet check
  costs zero tokens. Alerts, parked seats and new gate rows are the only things that wake you.
- Seats restart instead of `/clear` at about 150k tokens: handoff (`.fleet/handoff/<seat>.md`, newest on top),
  ship by pathspec, one message, restart. The watcher nudges them; `just fleet restart <seat>` is HUMAN.
- Anything that needs the human becomes ONE line that ends in a hard gate (`… && echo X-OK || { echo
  X-MISSING; exit 1; }`), queued with `just fleet gate-add`. Never "open a page and copy X".
- N workers is about N× your usage. `just fleet usage` before adding a seat; shrink before the limit.
- Every sequence done twice becomes a recipe. `just fleet mine` again in a week and show the new estimate.
