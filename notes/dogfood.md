Maintainer log.
# dogfood — fresh-repo loop (w3, 2026-10-13; claude 2.1.296, tmux 3.4) — clean 2× in a row

Fixed scratch path forever: /tmp/jiva-dogfood/nocode. Trust is per path and persists: reset its contents
between runs, never mint a new dir (same rule for any doctor case that boots a real claude).
Plain shell or any pane spawned after 53dcdb3 (P2), jiva's bin/ on PATH. Push target = local bare repo:
1. `cd /tmp/jiva-dogfood && rm -rf nocode origin.git && git clone -q --depth 1 https://github.com/kelseyhightower/nocode.git`
   `git clone -q --bare nocode origin.git && git -C nocode remote set-url origin "$PWD/origin.git" && cd nocode`
2. `jiva init` → .jiva/, `.jiva/` in .gitignore, CLAUDE.md (both left uncommitted — commit them yourself)
3. `JIVA_DESK=dogfood jiva up 1` → socket jiva-nocode: windows watchdog, queen, w1
4. New path only: trust dialog in queen + w1. `tmux -L jiva-nocode attach -t jiva:queen`, ↓ Enter, Ctrl-b n,
   ↓ Enter, Ctrl-b d. Sessions boot themselves (no re-run). Or pre-trust: run `claude` there once.
5. `jiva status` (expect "2 live") · `jiva dash start` / `jiva dash url` → http://127.0.0.1:<port>/
6. `jiva assign w1 card.md` (≤20 lines, a `Claim:` line) → comb: claim, done, ship; commit lands in origin.git
7. `jiva inbox` · `jiva pending` ("(nothing waiting)") · `jiva doctor` (all ok) · `jiva down` · `jiva up 1` · `jiva down`
Done = `tmux -L jiva-nocode ls` says no server. Pass takes ~1 min after trust.

## Papercut ledger (fixed sha | open → file:line)
P1 open  trust dialog: one keeper click per new repo path, by design (notes/perms.md). Step 4.
P2 fixed 53dcdb3 core/lib.sh: inherited JIVA_TARGET yields to PWD's repo outside it; explicit target wins.
P3 fixed core/jiva.sh cmdline: tmux server started inside claude leaked CLAUDECODE/CLAUDE_CODE_MESSAGING_*
         /SESSION_ID into every pane (live `jiva` server has them); panes unset $LEAKED. Verified via /proc.
P4 fixed core/jiva.sh ready(): trust hint says the session boots itself after the click.
P5 fixed core/pick.sh: no affinity.tsv + pipefail → printed w1 then exit 1; comb logged "pick: w1\nnone".
P6 fixed core/jiva.sh assign: comb line said "desk" whatever JIVA_DESK was.
P7 fixed core/verbs.sh pending: silent when nothing waits; hint was select-window (no attach) → attach -t jiva:<w>.
P8 fixed 53dcdb3 core/status.sh: status/bar/watch show "N at trust dialog".
P9 fixed 53dcdb3 core/lib.sh init_target: says .gitignore + CLAUDE.md are left uncommitted.
P10 fixed: core/roles/queen.md now points at the repo's own README/docs, not a JIVA plan file.
P11 fixed core/hooks/perm-relay.sh header said `just j-perm-answer` only; now names the .answer file.
