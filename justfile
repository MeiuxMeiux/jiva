set shell := ["bash", "-uc"]
default:
    @just --list
# repo: git init, hooks path, skeleton dirs
init:
    #!/usr/bin/env bash
    set -euo pipefail
    [[ -d .git ]] || git init -q -b main
    git config core.hooksPath .githooks
    chmod +x .githooks/pre-commit scripts/*.sh
    mkdir -p docs notes core plugin scripts packs/local .jiva \
      site/src/{css,js,fonts} site/art/{raw,final} site/build site/deploy
    for d in core plugin site/src/css site/src/js site/src/fonts site/art/final site/deploy; do
      [[ -n "$(ls -A "$d")" ]] || touch "$d/.gitkeep"
    done
    command -v gitleaks >/dev/null || echo "WARN: gitleaks not installed — commits will be blocked"
    echo "init ok"
# security: gitleaks secret scan over full history + trivy fs vuln/secret/misconfig, each when on PATH (else one WARN line)
sec:
    @if command -v gitleaks >/dev/null; then gitleaks git --redact --no-banner .; else echo "WARN sec: gitleaks not on PATH — secret scan skipped (https://github.com/gitleaks/gitleaks#installing)"; fi
    @if command -v trivy >/dev/null; then trivy fs --quiet --scanners vuln,secret,misconfig .; else echo "WARN sec: trivy not on PATH — vuln/secret/misconfig fs scan skipped"; fi

# budgets as tests: files ≤150 lines, notes ≤30, scripts parse, json valid
check:
    @core/jiva.sh check

# budgets as tests: boot payload, handoff/card sizes, state freshness, hooks, plugin mode; `live` adds the kill -9 self-heal test
doctor mode="":
    @core/jiva.sh doctor {{ if mode == "" { "" } else { quote(mode) } }}

# growth: rank repeated Bash commands/bigrams from this repo's transcripts (recipe candidates; `all` shows trivial keys)
mine n="10" all="":
    @core/jiva.sh mine {{quote(n)}} {{ if all == "" { "" } else { quote(all) } }}

# runtime: watchdog + seats on the private `tmux -L jiva` server — profile solo|duo[:N]|full[:N]|N, empty = auto (prints why)
up profile="":
    core/jiva.sh up {{quote(profile)}}

# plugin: local jiva plugin at user scope — status (exit 0 = installed) | mode (hooks source for `up`) | install | uninstall (ask the human first)
plugin action="status":
    @core/jiva.sh plugin {{quote(action)}}

# runtime: re-test version-sensitive assumptions on scratch socket jiva-spike (run after claude updates)
spike:
    @core/jiva.sh spike

# runtime: kill the jiva tmux server (never touches your own tmux)
down:
    core/jiva.sh down

# runtime: tier-2 phone feed — sanitized allowlisted .jiva/snapshot/snapshot.json (dash serves it + phone.html)
snapshot out="":
    @core/snapshot.sh {{ if out == "" { "" } else { quote(out) } }}

# runtime: tier-1 dashboard on 127.0.0.1:<random port> — start|stop|url
dash action="start":
    @core/jiva.sh dash {{quote(action)}}

# souls: name/color/avatar pack tooling — gen|check|show
roster action="check" pack="default":
    @core/jiva.sh roster {{quote(action)}} {{quote(pack)}}

# runtime: one-line fleet status from .jiva/state.json
status:
    @core/jiva.sh status

# boss: review a worker commit — stat, then check, then doctor (only non-ok lines)
review sha="HEAD":
    @git show --stat --format='%h %an %s' {{quote(sha)}} | head -25; core/jiva.sh check && echo "check ok"; core/jiva.sh doctor 2>&1 | grep -v '^ok' || echo "doctor ok"

# boss: lint a task card (≤20 lines + Area/Owned paths/Done-when, core/card.sh) then assign it — `just card w1 path/card.md`
card worker file:
    @core/card.sh {{quote(file)}} && core/jiva.sh assign {{quote(worker)}} {{quote(file)}}

# runtime: respawn the watchdog pane on this target's socket (after watchdog.sh edits; sessions untouched)
restart-watchdog:
    @core/jiva.sh restart-watchdog

# boss/desk: fleet at a glance — status, last 8 board lines + open asks
fleet:
    @core/jiva.sh status || true; core/jiva.sh inbox 8

# boss/desk: bar line, then the last n non-blank lines of a session's pane — `just peek w1 40`
peek name n="30":
    @. core/lib.sh; cat "$J/bar" 2>/dev/null; echo; T capture-pane -p -t "jiva:"{{quote(name)}} | grep -v '^[[:space:]]*$' | tail -n {{quote(n)}}

# boss/desk: say a line into a session, wait, then peek at it — `just tell w1 "status?" 8`
tell name text wait="8":
    @core/jiva.sh say {{quote(name)}} {{quote(text)}}; sleep {{quote(wait)}}; just peek {{quote(name)}} 20

# boss/desk: tmux windows, claude agents (name/status/waitingFor) and parked/flagged sessions
windows:
    @. core/lib.sh; T list-windows -t jiva -F '#I #W' 2>/dev/null; claude agents --json 2>/dev/null | jq -r '.[] | "\(.name // "-") \(.status) \(.waitingFor // "")"'; echo "parked: $(ls "$J/parked" 2>/dev/null | xargs) · flags: $(ls "$J/flags" 2>/dev/null | xargs)"

# desk: unpark a session a breaker parked (rm .jiva/parked/<name>); the watchdog may respawn it
unpark name:
    @n={{quote(name)}}; [[ $n =~ ^[A-Za-z0-9_-]+$ ]] || { echo "unpark: bad name" >&2; exit 1; }; . core/lib.sh; rm -v "$J/parked/$n"

# verb: claim paths before editing (directory-level, no overlaps)
[positional-arguments]
j-claim +paths:
    core/jiva.sh claim "$@"
# verb: drop paths from your own claims
[positional-arguments]
j-unclaim +paths:
    core/jiva.sh unclaim "$@"

# verb: report done|blocked|note "<msg>" (done runs core/check.sh)
j-report status msg:
    core/jiva.sh report {{quote(status)}} {{quote(msg)}}

# verb: typed ask for the desk: question, options, default, class (decision|permission|deploy|spend|…)
j-ask question options="" default="" class="decision":
    core/jiva.sh ask {{quote(question)}} {{quote(options)}} {{quote(default)}} {{quote(class)}}

# verb: commit claimed paths only and push under a lock
j-ship msg:
    core/jiva.sh ship {{quote(msg)}}

# verb: save a ≤40-line handoff from stdin or a file, then stop (watchdog respawns you)
j-handoff file="":
    core/jiva.sh handoff {{ if file == "" { "" } else { quote(file) } }}

# verb: recent board + open desk asks
j-inbox n="15":
    core/jiva.sh inbox {{quote(n)}}

# boss: give worker a ≤20-line task card (fresh body boots with it)
j-assign worker card:
    core/jiva.sh assign {{quote(worker)}} {{quote(card)}}

# desk: sessions stuck at a native prompt and where to answer them
j-pending:
    core/jiva.sh pending

# desk/human: answer an open ask (no text = its default); the asker gets "JIVA answer <id>: <text>"
j-answer id text="":
    core/jiva.sh answer {{quote(id)}} {{quote(text)}}
# human: answer a relayed permission ask (only if perm-relay.sh is wired in)
j-perm-answer id decision:
    @echo {{quote(decision)}} > .jiva/asks/{{quote(id)}}.answer && echo "answered "{{quote(id)}}": "{{quote(decision)}}

# wsl: hidden Windows-side keepalive so tmux survives closing the terminal (run it yourself: `! just keepalive`)
keepalive action="start":
    @[[ -n ${WSL_DISTRO_NAME:-} ]] || { echo "keepalive: WSL only, skipped"; exit 0; }; core/keepalive.sh {{quote(action)}}
import? 'site/site.just'   # site module (w2 owns site/)
import? 'core/fleet.just'  # fleet module: desk-digest, profile, gate-*
# HUMAN-ONLY: deploy site to jiva.meiuxmeiux.com (atomic release, keeps 5) | rollback | verify
deploy action="deploy":
    scripts/deploy.sh {{quote(action)}}
