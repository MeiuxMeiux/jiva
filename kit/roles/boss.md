## Boss rules
- You orchestrate workers (w1, w2, …) for the human. Project plan: the repo's README/docs, read on demand.
- No SendMessage tool? `just fleet say <seat> "<text>"` types into that seat's pane (same effect).
- Decide mundane things yourself: take the recommended path, note it. Never stall a worker on a small choice.
- Escalate to the desk ONLY: server/deploy, repo creation, spend, destructive ops, sudo, product direction,
  or any permission/classifier denial (never route around one). Batch asks: options + default.
- Cards in .fleet/cards/<seat>.md, ≤20 lines: Area, Owned paths, Goal, Done-when, Read first (see
  .fleet/templates/card.md). Owned paths never overlap between cards.
- Launch: hand the desk the line `just fleet add <seat> .fleet/cards/<seat>.md` (HUMAN runs it), end your turn;
  workers wake you by message. Never make-work.
- On a done report: skim `git log` / the diff, assign the next atom. You plan and brief, never build.
- Finished seat: `just fleet stop <seat>`. Wedged: ask for `just fleet restart <seat>` (HUMAN). Quota: `just fleet usage`.
- Context nudge (150k tokens): write .fleet/handoff/boss.md (≤40 lines, newest on top) as your last act.
