#!/usr/bin/env bash
# spike — re-test the version-sensitive assumptions in notes/core.md, non-interactively. Two cheap sessions
# (sp1, sp2) on the scratch socket `jiva-spike` (never the live fleet's), torn down by trap. One line per check:
#   agents   `claude agents --json` lists both with pid/name/status
#   wake     an idle peer goes busy ≤10s after `say` (SendMessage-free)
#   context  SessionStart additionalContext arrives (a nonce rides in as the desk name; the reply shows it)
#   status   the status line writes $J/state/<name>.json
# Trust dialog on screen → every check prints `skip` with the attach hint (never auto-accepted).
# Model: $JIVA_SPIKE_MODEL, else alias haiku (cheap). Exit 1 on any FAIL.
set -uo pipefail
# shellcheck source=core/lib.sh
source "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")/lib.sh"
SS=jiva-spike; MODEL="${JIVA_SPIKE_MODEL:-haiku}"; NONCE="desk$RANDOM$RANDOM"; bad=0
S() { tmux -L "$SS" "$@"; }
ok() { printf 'ok    %s\n' "$1"; }
no() { printf 'FAIL  %s\n' "$1"; bad=1; }
cleanup() { S kill-server 2>/dev/null; rm -f "$J/state/sp1.json" "$J/state/sp2.json"; }
trap cleanup EXIT
screen() { S capture-pane -p -t "spike:$1" 2>/dev/null; }
agent() { # name → {pid,name,status} json for that session in this target, or empty
  claude agents --json 2>/dev/null | jq -c --arg n "$1" --arg r "$TARGET" \
    '[.[] | select(.name == $n and .cwd == $r) | {pid, name, status}] | first // empty'
}

echo "spike: $(claude --version 2>/dev/null | head -1) · model $MODEL · socket $SS" >&2
cleanup; render_settings
S new-session -d -s spike -n shell -x 200 -y 50 -c "$TARGET"
for n in sp1 sp2; do
  S new-window -d -t spike -n "$n" -c "$TARGET" "$(printf \
    'PATH=%q:$PATH JIVA_HOME=%q JIVA_TARGET=%q JIVA_ROLE=spike JIVA_NAME=%q JIVA_DESK=%q claude --model %q --name %q --settings %q; exec bash' \
    "$JIVA_HOME/bin" "$JIVA_HOME" "$TARGET" "$n" "$NONCE" "$MODEL" "$n" "$J/settings.json")"
done

for n in sp1 sp2; do # wait for the input prompt; a trust dialog is the human's click
  for _ in $(seq 60); do
    s="$(screen "$n")"
    if grep -q 'trust this folder' <<<"$s"; then
      for c in agents wake context status; do printf 'skip  %s (trust dialog)\n' "$c"; done
      echo "accept once: tmux -L $SS attach -t spike:$n  (then rerun; this run's server is killed on exit)" >&2
      exit 0
    fi
    grep -q 'for agents' <<<"$s" && continue 2
    sleep 1
  done
  no "$n never reached the prompt"; exit 1
done

# (a) agents --json has pid/name/status for both
a1="" a2=""
for _ in $(seq 15); do
  a1="$(agent sp1)"; a2="$(agent sp2)"
  [[ -n $a1 && -n $a2 ]] && break; sleep 1
done
if [[ -n $a1 && -n $a2 ]] && jq -e 'select(.pid and .name and .status)' <<<"$a1" >/dev/null &&
   jq -e 'select(.pid and .name and .status)' <<<"$a2" >/dev/null; then
  ok "agents: sp1 $(jq -r '"\(.pid) \(.status)"' <<<"$a1"), sp2 $(jq -r '"\(.pid) \(.status)"' <<<"$a2")"
else no "agents: missing pid/name/status (sp1='$a1' sp2='$a2')"; fi

# (b) idle peer wakes on say and goes busy ≤10s
st="$(agent sp2 | jq -r '.status // "?"')"
S send-keys -t spike:sp2 -l "What is your Desk session name? Reply with only that word."
sleep 0.3; S send-keys -t spike:sp2 Enter
t0=$SECONDS busy=""
while (( SECONDS - t0 <= 10 )); do
  [[ $(agent sp2 | jq -r '.status // empty') == busy ]] && { busy=$((SECONDS - t0)); break; }
  sleep 0.5
done
[[ -n $busy ]] && ok "wake: sp2 $st → busy in ${busy}s" || no "wake: sp2 ($st) not busy within 10s of say"

# (c) SessionStart additionalContext: the nonce exists only there
got=""
for _ in $(seq 60); do screen sp2 | grep -q "$NONCE" && { got=1; break; }; sleep 1; done
[[ -n $got ]] && ok "context: SessionStart additionalContext seen ($NONCE)" ||
  no "context: nonce $NONCE never appeared in sp2's pane"

# (d) status line writes $J/state/<name>.json (fresh)
got=""
for _ in $(seq 20); do
  [[ -s $J/state/sp2.json ]] && (( $(date +%s) - $(jq -r '.ts // 0' "$J/state/sp2.json") <= 120 )) && { got=1; break; }
  sleep 1
done
[[ -n $got ]] && ok "status: statusline wrote state/sp2.json ($(jq -c '{tok,pct}' "$J/state/sp2.json"))" ||
  no "status: no fresh $J/state/sp2.json"
# a green spike records its version; doctor-budgets WARNs spike-stale when `claude --version` moves past it
(( bad )) || claude --version 2>/dev/null | grep -oE '^[0-9]+(\.[0-9]+)+' > "$J/spike.version"
exit $bad
