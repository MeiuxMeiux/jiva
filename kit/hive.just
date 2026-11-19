# hive.just — the kit's verbs. Installed as .hive/hive.just; add `mod hive '.hive/hive.just'` to your
# justfile and run `just hive <recipe>` (or `just -f .hive/hive.just <recipe>` without a justfile).
# Scripts find the repo root via git, so recipes work from any directory. KEEPER-ONLY: up, add, restart, down, gate-run go.

bin := source_directory() / "bin"

# list the recipes
default:
    @just -f {{quote(source_file())}} --list

# the whole kit against a scratch repo with a FAKE claude (no cells, no tokens): run it before the first `up`
selftest:
    @bash {{quote(source_directory() / "test.sh")}}

# KEEPER: private tmux server + the zero-token watch window (fresh server clears stale launch files + claims)
up:
    @{{bin}}/hive.sh up

# KEEPER: cell a worker on a card (needs Area:/Owned paths:/Done-when:) — `just hive add w1 .hive/cards/w1.md`
[no-cd]
add cell card:
    @{{bin}}/hive.sh add {{quote(cell)}} {{quote(card)}}

# cells at a glance: state, tokens, area
ls:
    @{{bin}}/hive.sh ls

# last n non-blank lines of a cell's pane
peek cell n="30":
    @{{bin}}/hive.sh peek {{quote(cell)}} {{quote(n)}}

# type a line into a cell (long text: write a file, send the path)
say cell text:
    @{{bin}}/hive.sh say {{quote(cell)}} {{quote(text)}}

# KEEPER: fresh body for a cell (it reads its handoff, then its card)
restart cell:
    @{{bin}}/hive.sh restart {{quote(cell)}}

# kill a cell's window and forget it (watch stops relaunching it)
stop cell:
    @{{bin}}/hive.sh stop {{quote(cell)}}

# KEEPER: kill the private hive server (your own tmux is untouched)
down:
    @{{bin}}/hive.sh down

# one watch tick now (dead cells, dialogs, context nudges → .hive/state/alerts.log)
watch-once:
    @{{bin}}/watch.sh once

# claim globs for $FLEET_NAME (default desk) before editing; overlaps are refused
[positional-arguments]
claim +globs:
    @{{bin}}/claim.sh claim "$@"

# drop your own claims (globs or `all`)
[positional-arguments]
release +globs:
    @{{bin}}/claim.sh release "$@"

# every claim, one "<cell> <glob>" per line
claims:
    @{{bin}}/claim.sh list

# commit ONLY your claimed paths by pathspec (never add -A)
ship msg:
    @{{bin}}/claim.sh ship {{quote(msg)}}

# propose ONE gated line for the keeper (linted: ends in X-OK/X-MISSING + exit 1, no $VAR in '…' sed/awk)
gate-add line why="":
    @{{bin}}/gate.sh add {{quote(line)}} {{quote(why)}}

# every gate row with its status
gate-list:
    @{{bin}}/gate.sh list

# KEEPER: no args = plan; `just hive gate-run go <ids…>` runs exactly those rows (refused inside a cell)
[positional-arguments]
gate-run *args:
    @{{bin}}/gate.sh run "$@"

# a gate row's status + output tail; exit 0 ok, 1 fail, 2 pending
gate-result id n="15":
    @{{bin}}/gate.sh result {{quote(id)}} {{quote(n)}}

# rank the Bash commands past sessions here repeated (recipe candidates) + a token estimate; `all` shows trivial keys
mine n="10" all="":
    @{{bin}}/mine.sh {{quote(n)}} {{ if all == "" { "" } else { quote(all) } }}

# desk timer tick: prints only what changed (alerts, gate rows, parked, cells); silent when quiet
digest:
    @{{bin}}/watch.sh digest

# per-cell tokens + max 5h/7d % from .hive/state/*.json (statusline.sh); one WARN line at ≥85%
usage:
    #!/usr/bin/env bash
    set -uo pipefail
    s="$(git rev-parse --show-toplevel)/.hive/state"; shopt -s nullglob; fs=("$s"/*.json)
    (( ${#fs[@]} )) || { echo "usage: no cell json yet (statusline.sh writes .hive/state/<cell>.json)"; exit 0; }
    for f in "${fs[@]}"; do printf '%-10s %5sk\n' "$(basename "$f" .json)" "$(jq -r '(.tok // 0) / 1000 | floor' "$f")"; done
    read -r q5 q7 < <(jq -rs '[([.[].q5h | numbers] | max // 0 | floor), ([.[].q7d | numbers] | max // 0 | floor)] | @tsv' "${fs[@]}")
    echo "quota: 5h ${q5}% · 7d ${q7}%"
    (( q5 >= 85 || q7 >= 85 )) && echo "WARN quota ≥85% — shrink the hive (just hive stop <cell>) before the limit" || true
