# AREAS — one row per area: owned paths, the ONE note to read first, what needs the keeper
Cards name one `Area:` from this table. `just card` needs `Area:`, `Owned paths:` and `Done-when:` (older `Claim:` / `Done-check:` lines count too).
Rules and their reasons: docs/agents/RULES.md. A note is ≤30 lines; read only the one your area names.

| area | paths | read first | needs the keeper |
|---|---|---|---|
| core | core/jiva.sh core/lib.sh core/verbs.sh core/watchdog.sh | notes/core.md | settings/allow rules, ~/.claude |
| hive | core/profile.sh core/gate.sh core/digest.sh core/card.sh core/hive.just core/roles/ docs/agents/ | notes/hive.md | `just gate-run go`, role edits behind plugin skill symlinks |
| perms | core/hooks/guard.sh core/hooks/perm-relay.sh core/asks.sh | notes/perms.md | trust dialog, allow rules, protected asks |
| breakers | core/breakers.sh core/governor.sh core/lease.sh | notes/breakers.md | unpark (`just unpark`), resume a paused hive |
| watch | core/watch.sh core/status.sh | notes/watch.md | — |
| notify | core/notify.sh | notes/notify.md | ntfy url (JIVA_NOTIFY_NTFY) |
| history | core/history.sh | notes/history.md | — |
| dash | core/dash* core/phone* core/snapshot.sh | notes/dash.md | exposing it beyond 127.0.0.1 |
| doctor | core/doctor*.sh core/check.sh core/spike.sh | notes/doctor.md | — |
| plugin | plugin/ | notes/plugin.md | install/uninstall, SKILL.md symlinks (KEEPER-only) |
| roster | packs/ scripts/roster.sh | notes/roster.md | anything in packs/local/ (private) |
| art | scripts/art-* site/art/ | notes/art.md | image spend > $2 |
| site | site/ scripts/deploy.sh | notes/site.md | `just deploy`, DNS, server changes |
| dogfood | a scratch repo outside this tree | notes/dogfood.md | first trust click per path |
| plan | docs/history/PLAN.md docs/history/KICKOFF.md | notes/plan-audit.md | product direction |
