# JIVA Kit: one file, and the agent you already have sets up the hive with you

Put this file in any git repo as `KIT.md`, open Claude Code there, and say:

**"Read KIT.md. You are my desk now. Start at Step 0 and stop after every step so we can look together."**

The agent reading this becomes the **desk**: the one cell you talk to. It installs the files at the bottom
of this page into `.hive/`, then works through the steps *with* you: tidies the markdown your sessions boot
with, sets up `just`, mines your past conversations for recipes (and tells you what they would have saved),
and ends by telling you the hive is ready and how to run it. It never deploys, pushes or launches cells:
those lines are handed to you to run. The why behind every step: JIVA Micro (`micro.md`, next to this file).
It is plain markdown: read it before you hand it to an agent. Source, file by file:
https://github.com/MeiuxMeiux/jiva/tree/main/kit (the full runner with watchdog, dashboard and verbs lives there too).

Needs: Linux or WSL2, bash 4+, git, tmux 3.2+, jq, just, flock (util-linux), Claude Code. On Debian/Ubuntu:
`sudo apt install tmux jq` and `just` from https://just.systems/man/en/packages.html (apt's is too old).
Cost: each cell is a full Claude Code session on your plan (`opus` by default; `FLEET_MODEL=sonnet` to change),
so N cells draw N times your usual rate. Measured here: a busy Opus worker reports about $1.75 of API-equivalent
usage per 90k of context, so a body that lives to its 200k rotation is roughly $4 at API prices; on a Max plan
that is quota, and `just hive usage` shows the 5h/7d percentages. Steps 2–3 edit the markdown your sessions boot with (CLAUDE.md, memory,
rules): every edit is shown as a diff first and nothing is deleted, only moved.

## If you are the agent reading this
- You are the desk for the rest of this session. Work *with* the keeper: show, ask, then change. After each
  step print a short report and stop. Never run a line marked KEEPER; print it for them instead.
- Decisions go in front of the keeper as options, recommended first. Mundane choices you take yourself and say so.
- Every edit to the keeper's files is shown as a diff first. You never delete their notes: you move them.
- When a step cannot be done here (missing tool, denied permission), say what is missing and the one line that
  fixes it. Never route around a denial.

## Step 0: install the files (you, the agent)
1. Copy each block under **Files** to the path in its heading (`.hive/<path>`; the `hive.just` block →
   `.hive/hive.just`), then `chmod +x .hive/bin/*.sh`.
2. Add `mod hive '.hive/hive.just'` to the repo's `justfile` (create one if there is none). Every hive
   recipe is then `just hive <recipe>`; `just hive` lists them.
3. `echo '.hive/state/' >> .gitignore` (runtime state: claims, cell json, alerts, gate results).
4. Merge the keys of `.hive/settings.json` (statusLine, permissions.allow) into `.claude/settings.json`; none yet →
   copy it. With one, merge into a temp file, show the diff, then move it over:
   `jq -s '.[0] as $a | .[1] as $b | $a * $b | .permissions.allow = (($a.permissions.allow // []) + $b.permissions.allow | unique)' .claude/settings.json .hive/settings.json`
5. `just hive selftest`: the whole kit against a scratch repo with a fake `claude` (no cells, no tokens). All
   lines must read `ok`; a `FAIL` names the piece that does not work on this machine. Fix or report it, never skip it.
6. Report: `just hive` output, `tmux -V`, `jq --version`, `claude --version`, `git status --short`.

No agent at hand? The same install by hand, from the repo root (python3), then steps 2–5 above:
```bash
python3 - KIT.md <<'EOF'
import re, sys, pathlib
t = open(sys.argv[1], encoding='utf-8').read()
for p, f, b in re.findall(r'^### (\.hive/\S+)\n(`{3,})\w*\n(.*?)\n\2\n', t, re.S | re.M):
    pathlib.Path(p).parent.mkdir(parents=True, exist_ok=True); pathlib.Path(p).write_text(b + '\n', encoding='utf-8'); print(p)
EOF
chmod +x .hive/bin/*.sh
```

## Step 1: measure (read-only)
1. `nproc`, `free -m`: about 1 GB RAM and 1 core per cell. Fewer than 3 cells fit → solo mode (desk + 1 worker).
2. Quota: ask the keeper to run `/context` in a fresh session and paste it. Note the tokens taken by the
   system tools, MCP tools, memory files and the CLAUDE.md chain. Write them down: **before**.
3. Is anything here live in production? Only then is a loop cell worth it. Who else commits here?
4. Report before/after will come at the end of Step 2; for now the numbers and the cell count you recommend.

## Step 2: tidy the startup files, together (the biggest lever: every line costs every cell on every restart)
Startup files = whatever Claude Code loads before the first word: the root `CLAUDE.md`, `CLAUDE.md` in
subdirectories, `~/.claude/CLAUDE.md`, memory (`MEMORY.md` + memory files), rules, and MCP servers.
1. List them with line counts. Show the keeper what loads and roughly what it costs.
2. Root `CLAUDE.md` becomes a router of 40 lines or fewer, built from `.hive/templates/CLAUDE.md`: a scope
   guard, one line per rule, pointers. Every paragraph that is detail moves to `notes/<area>.md` (30 lines or
   fewer each) or `docs/agents/*.md`, read on demand. Propose the split as a table (line → where it goes),
   get a yes, then do it. Never drop a rule the keeper wrote: move it and link it.
3. Subdirectory `CLAUDE.md`: one line per rule. Memory: `MEMORY.md` is an index, one line ≤140 characters
   per memory, one fact per file; a long index gets truncated and silently drops the newest lines.
4. MCP: cells launch with `--strict-mcp-config` unless their card needs a connector. List the servers and
   the ones a worker never needs.
5. Ask for `/context` again and show **before → after** per line item. One hive measured 56k → 24k per cell.

## Step 3: `just` is the blessed path (mine the past for recipes)
Cells call recipes, never raw tmux or git: one place for guards and logs, and the output is what the recipe
chose to print, not a screenful.
1. `just hive mine 15`: ranks the Bash commands your past sessions in this repo repeated (freq × output size ×
   retries) and ends with the estimate: tokens those repeats cost, and what recipes that print only what
   changed would have kept out of context. Show the table and the estimate.
2. Propose 3 to 6 recipes from the top rows: name, one-line comment, what it prints. Writes print what they
   did and exit non-zero on surprise; anything that sends (mail, chat, push) takes `--dry-run`.
3. Write the ones the keeper picks into the root `justfile`, run each once, show the output. Add the line
   "Run `just --list` first; prefer recipes over ad-hoc shell. A sequence done twice → propose a recipe." to
   `CLAUDE.md` if it is not there.

## Step 4: rules, roles and the first card
1. `.hive/templates/rules.md` → `.hive/rules.md`, linked from `CLAUDE.md`. Read it with the keeper: each
   line is a rule and the afternoon it cost somebody. Drop none, add theirs.
2. Role sheets are already in `.hive/roles/` (desk, queen, worker, loop). Explain the shape in five lines:
   desk relays and decides nothing keeper-only; queen plans and writes cards, never builds; workers own paths
   and build; watch is a bash loop with no model. Solo mode: no queen, the desk writes the cards.
3. Write the first card with the keeper, from `.hive/templates/card.md`, as `.hive/cards/w1.md`: Area,
   Owned paths, Goal, Done-when, Read first. A card missing any of them is refused by `just hive add`.

## Step 5: launch (KEEPER runs the lines; you print them)
`just hive selftest` green first (Step 0.5). Then:
```bash
just hive up                              # private tmux server `tmux -L hive` + zero-token watch window
just hive add w1 .hive/cards/w1.md       # cell w1 on its card (reads .hive/roles/worker.md first)
```
First run in a repo, Claude Code shows a workspace-trust dialog once: `tmux -L hive attach`, accept it, detach
(`Ctrl-b d`). Then confirm with `just hive ls` and `just hive peek w1`. `ls` states: `live` is good; `dead` means the
body exited (watch relaunches it within a tick); `parked` is a crash loop (3 deaths in 60 s): `peek` it, fix the cause,
`rm .hive/state/parked/w1`. When w1 shows live, say it plainly:

> **Your hive is ready.** One worker on w1, watch running, claims and gates armed.

Then print the daily cheat sheet:
- `just hive ls` cells + tokens · `just hive peek w1 40` its screen · `just hive say w1 "…"` talk to it
- `just hive add w2 .hive/cards/w2.md` another cell · `just hive stop w2` done · `just hive restart w1` wedged
- `just hive claims` who owns what · `just hive gate-list` lines waiting for you · `just hive gate-run go <id>`
- `just hive usage` quota · `just hive digest` what changed · `just hive down` all off (your tmux untouched)

## Step 6: rhythm (how the desk lives from now on)
- One Monitor on `just hive digest` every 10 minutes: it prints nothing when nothing changed, so a quiet check
  costs zero tokens. Alerts, parked cells and new gate rows are the only things that wake you.
- Cells restart instead of `/clear` at about 150k tokens: handoff (`.hive/handoff/<cell>.md`, newest on top),
  ship by pathspec, one message, restart. The watcher nudges them; `just hive restart <cell>` is KEEPER.
- Anything that needs the keeper becomes ONE line that ends in a hard gate (`… && echo X-OK || { echo
  X-MISSING; exit 1; }`), queued with `just hive gate-add` and run by `just hive gate-run go <id>` (a subshell).
  Never paste a gate line into a login shell: its `exit 1` closes the terminal. Never "open a page and copy X".
- N workers is about N× your usage. `just hive usage` before adding a cell; shrink before the limit.
- Every sequence done twice becomes a recipe. `just hive mine` again in a week and show the new estimate.
