# fleet.just — the kit's verbs. Installed as .fleet/fleet.just; add `mod fleet '.fleet/fleet.just'` to your
# justfile and run `just fleet <recipe>` (or `just -f .fleet/fleet.just <recipe>` without a justfile).
# Scripts find the repo root via git, so recipes work from any directory. HUMAN-ONLY: up, add, restart, down, gate-run go.

bin := source_directory() / "bin"

# list the recipes
default:
    @just -f {{quote(source_file())}} --list

# HUMAN: private tmux server + the zero-token watch window (fresh server clears stale launch files + claims)
up:
    @{{bin}}/fleet.sh up

# HUMAN: seat a worker on a card (needs Area:/Owned paths:/Done-when:) — `just fleet add w1 cards/w1.md`
add seat card:
    @{{bin}}/fleet.sh add {{quote(seat)}} {{quote(card)}}

# seats at a glance: state, tokens, area
ls:
    @{{bin}}/fleet.sh ls

# last n non-blank lines of a seat's pane
peek seat n="30":
    @{{bin}}/fleet.sh peek {{quote(seat)}} {{quote(n)}}

# type a line into a seat (long text: write a file, send the path)
say seat text:
    @{{bin}}/fleet.sh say {{quote(seat)}} {{quote(text)}}

# HUMAN: fresh body for a seat (it reads its handoff, then its card)
restart seat:
    @{{bin}}/fleet.sh restart {{quote(seat)}}

# kill a seat's window and forget it (watch stops relaunching it)
stop seat:
    @{{bin}}/fleet.sh stop {{quote(seat)}}

# HUMAN: kill the private fleet server (your own tmux is untouched)
down:
    @{{bin}}/fleet.sh down

# one watch tick now (dead seats, dialogs, context nudges → .fleet/alerts.log)
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

# every claim, one "<seat> <glob>" per line
claims:
    @{{bin}}/claim.sh list

# commit ONLY your claimed paths by pathspec (never add -A)
ship msg:
    @{{bin}}/claim.sh ship {{quote(msg)}}

# propose ONE gated line for the human (linted: ends in X-OK/X-MISSING + exit 1, no $VAR in '…' sed/awk)
gate-add line why="":
    @{{bin}}/gate.sh add {{quote(line)}} {{quote(why)}}

# every gate row with its status
gate-list:
    @{{bin}}/gate.sh list

# HUMAN: no args = plan; `just fleet gate-run go <ids…>` runs exactly those rows (refused inside a seat)
[positional-arguments]
gate-run *args:
    @{{bin}}/gate.sh run "$@"

# a gate row's status + output tail; exit 0 ok, 1 fail, 2 pending
gate-result id n="15":
    @{{bin}}/gate.sh result {{quote(id)}} {{quote(n)}}

# rank the Bash commands past sessions here repeated (recipe candidates) + a token estimate; `all` shows trivial keys
mine n="10" all="":
    @{{bin}}/mine.sh {{quote(n)}} {{ if all == "" { "" } else { quote(all) } }}

# desk timer tick: prints only what changed (alerts, gate rows, parked, seats); silent when quiet
digest:
    @{{bin}}/watch.sh digest

# per-seat tokens + max 5h/7d % from .fleet/state/*.json (statusline.sh); one WARN line at ≥85%
usage:
    #!/usr/bin/env bash
    set -uo pipefail
    s="$(git rev-parse --show-toplevel)/.fleet/state"; shopt -s nullglob; fs=("$s"/*.json)
    (( ${#fs[@]} )) || { echo "usage: no seat json yet (statusline.sh writes .fleet/state/<seat>.json)"; exit 0; }
    for f in "${fs[@]}"; do printf '%-10s %5sk\n' "$(basename "$f" .json)" "$(jq -r '(.tok // 0) / 1000 | floor' "$f")"; done
    read -r q5 q7 < <(jq -rs '[([.[].q5h | numbers] | max // 0 | floor), ([.[].q7d | numbers] | max // 0 | floor)] | @tsv' "${fs[@]}")
    echo "quota: 5h ${q5}% · 7d ${q7}%"
    (( q5 >= 85 || q7 >= 85 )) && echo "WARN quota ≥85% — shrink the fleet (just fleet stop <seat>) before the limit" || true
