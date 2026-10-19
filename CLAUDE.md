# JIVA
- On boot, if `.jiva/handoff/desk.md` exists, read it first — it is your previous life's handoff.
- Run `just --list` first; prefer recipes over ad-hoc shell. Repeat a sequence twice → propose a recipe.
- Router: `docs/agents/GLOSSARY.md` (hive words) + `docs/agents/AREAS.md` (area → paths, the ONE note, keeper-only items) + `docs/agents/RULES.md` (rules + why). Other `docs/` on demand.
- Never print secrets: keys are read only inside scripts via `scripts/keys.sh` (`JIVA_KEYS_DIR`, default `/var/keys`).
- No copyrighted art in git; test rosters go in `packs/local/` (gitignored).
- Hive verbs: `jiva claim|report|ask|ship|handoff|inbox|pending` (bin/jiva; `just j-*` wrap them).
- Ask the keeper before: repo creation, image spend > $2, server changes beyond `just deploy`.
- Files ≤150 lines; notes ≤30 lines.
