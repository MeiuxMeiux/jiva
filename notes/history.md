# history — cumulative fleet history (core/history.sh, sourced; `jiva history [n]` = tail)
File `.jiva/history.jsonl`: one compact JSON object per line, append-only (flock, never rewritten/trimmed).
Every line: `ts` (epoch s, number) · `kind` · `who` (writer's JIVA_NAME; watchdog lines say `watchdog`).
Strings ≤80 chars, control chars → space. Numbers stay numbers, except id/sha/name/by/class/st/why/trip
(always strings). Never prompts, card bodies, diffs or file text. Unknown kinds may appear later: skip them.
Session events carry `name` (the session) since `who` is the watchdog. Kinds and their extra fields:
- `claim` n:number (paths claimed) — verbs.sh
- `report` st:"done"|"blocked"|"note" — verbs.sh (done only after check passed)
- `ship` sha:string (short HEAD after the commit; no-op ships emit nothing) — verbs.sh
- `handoff` lines:number — verbs.sh
- `ask` id:string class:"decision"|permission|deploy|spend|destructive|sudo|remote|license — asks.sh
- `answer` id:string by:string (answerer's name) — asks.sh
- `expire` id:string class:"decision" (deadline passed, default applied) — asks.sh, from the watchdog
- `nudge` name tok:number (context nudge at 75% of ceiling = 150k of 200k) — watchdog.sh
- `life` name why:"rotate"|"heal" [tok:number on rotate = tokens at rotation] — a new life starts
- `heal` name (dead/missing pane respawned) — breakers.sh; always followed by `life` why:"heal"
- `park` name why:"storm"|"heal-storm" [tok:number on storm] — breakers.sh
- `trip` name trip:string (first word of a new flag: burn|storm|ceiling|time|usd|heal-storm|disk-full;
  `name` = flag file name, a session or a global) — breakers.sh flag(); quota excluded
- `quota` st:"pause"|"resume" q5h:number q7d:number (governor crosses JIVA_QUOTA_MAX 85%) — watchdog.sh
- `lease` st:"stale"|"fresh" [age:number on stale] — lease.sh, on transitions only
- `tok` tok:number (fleet total) s:{name: tok} q5h:number|null q7d:number|null — watchdog,
  at most every JIVA_HIST_TOK=300 s (last write epoch in `.jiva/history.tok`)
Not here: dash.sh start/stop (w4). Test: `jiva doctor history` (core/doctor-history.sh, scratch J).
