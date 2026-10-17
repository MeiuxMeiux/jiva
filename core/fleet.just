# fleet recipes (lane A; imported by the root justfile). Facts: notes/fleet.md; rules: docs/agents/RULES.md.

# desk: zero-token Monitor tick — prints nothing unless pushes/asks/gate rows/alerts/parked/flags changed since last run
desk-digest:
    @core/digest.sh

# fleet: what `just up [profile]` would start and why (solo|duo[:N]|full[:N]|N; empty = auto from host + quota)
profile p="":
    @core/profile.sh {{quote(p)}}

# verb: propose ONE gated shell line for the human to run — `just gate-add "<line>" "why" [deps]` (linted)
gate-add line why="" deps="":
    @core/gate.sh add {{quote(line)}} {{quote(why)}} {{quote(deps)}}

# verb: replace a wrong gate row with a corrected NEW row (the old one is superseded, never edited)
gate-fix id line why="" deps="":
    @core/gate.sh fix {{quote(id)}} {{quote(line)}} {{quote(why)}} {{quote(deps)}}

# HUMAN-ONLY: no args = plan (what would run); `just gate-run go <ids…>` runs exactly those rows in order, deps enforced
[positional-arguments]
gate-run *args:
    @core/gate.sh {{ if args == "" { "plan" } else { "" } }} "$@"

# verb: check a gate row you asked for — status + output tail; exit 0 ok, 1 fail, 2 not run yet
gate-result id n="15":
    @core/gate.sh result {{quote(id)}} {{quote(n)}}
