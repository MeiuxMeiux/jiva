#!/usr/bin/env bash
# kit/test.sh — the whole kit against a scratch git repo with a FAKE `claude` on PATH: no real seats, no spend.
# Private socket fleet-kit-test; scratch /tmp/jiva-scratch/kit-test (wiped on exit). Exit 0 = all green.
set -uo pipefail
KIT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
X=/tmp/jiva-scratch/kit-test; R=$X/repo; export FLEET_SOCK=fleet-kit-test
cleanup() { tmux -L fleet-kit-test kill-server 2>/dev/null; rm -rf /tmp/jiva-scratch/kit-test; }
trap cleanup EXIT; cleanup; mkdir -p "$R" "$X/bin"
pass=0; fail=0
ok() { if eval "$2" >/dev/null 2>&1; then pass=$((pass + 1)); echo "ok   $1"; else fail=$((fail + 1)); echo "FAIL $1"; fi; }
until_() { local _; for _ in $(seq 50); do eval "$1" >/dev/null 2>&1 && return 0; sleep 0.1; done; return 1; }

cat > "$X/bin/claude" <<EOF
#!/usr/bin/env bash
# fake claude: logs its args + leaked env, echoes input; "die" exits, "dialog" shows a permission prompt
echo "args: \$* CLAUDECODE=\${CLAUDECODE:-unset}" >> $X/fake.log
[[ -e $X/die ]] && exit 1
echo "fake claude ready for agents"
while read -r l; do case \$l in die) exit 0 ;; dialog) echo "Do you want to proceed?" ;; *) echo "got: \$l" ;; esac; done
EOF
chmod +x "$X/bin/claude"; export PATH="$X/bin:$PATH" CLAUDECODE=1   # the leak fleet.sh must scrub

cd "$R" && git init -q && git config user.email t@t && git config user.name t
mkdir -p .fleet src docs && cp -r "$KIT/bin" "$KIT/fleet.just" "$KIT/settings.json" .fleet/
printf '.fleet/state/\n' > .gitignore; echo a > src/a.js; echo d > docs/x.md
printf "mod fleet '.fleet/fleet.just'\n" > justfile; git add -A && git commit -qm init
printf 'Area: demo\nOwned paths: src/\nGoal: echo\nDone-when: never\n' > card.md
B=.fleet/bin; F=".fleet/bin/fleet.sh"; S=.fleet/state

echo "-- fleet.sh"
ok "up starts the private server + watch window" "$F up && tmux -L fleet-kit-test list-windows -t fleet -F '#W' | grep -qx watch"
ok "card without Done-when is refused" "! $F add w9 <(printf 'Area: x\nOwned paths: y\n')"
ok "add seats w1 (launch file + window)" "$F add w1 card.md && test -e $S/launch/w1"
ok "fake claude booted lean, leak scrubbed" "until_ 'grep -q strict-mcp-config $X/fake.log' && grep -q 'CLAUDECODE=unset' $X/fake.log"
ok "ls lists w1 live" "until_ \"$F ls | grep -q 'w1 *live'\""
ok "say + peek round-trip" "$F say w1 'hello fleet' && until_ \"$F peek w1 | grep -q 'got: hello fleet'\""
ok "just module wraps it (just fleet ls)" "just fleet ls | grep -q w1"
cp card.md .fleet/cards/w2.md
ok "just fleet add takes the documented .fleet/cards path from the repo root" "just fleet add w2 .fleet/cards/w2.md && test -e $S/launch/w2 && $F stop w2"

echo "-- watch.sh (one tick each)"
echo '{"tok":160000}' > $S/w1.json
ok "ctx ≥150k nudges once" "$B/watch.sh once && until_ \"$F peek w1 | grep -q 'FLEET watch: context at 160000'\""
echo '{"tok":190000}' > $S/w1.json
ok "ctx ≥185k alerts" "$B/watch.sh once && grep -q 'w1 context 190000' $S/alerts.log"
$F say w1 dialog; until_ "$F peek w1 | grep -q 'Do you want'"
ok "dialog stall alerts" "$B/watch.sh once && grep -q 'w1 stalled on a dialog' $S/alerts.log"
$F say w1 die; until_ "tmux -L fleet-kit-test list-panes -t fleet:w1 -F '#{pane_dead}' | grep -qx 1"
ok "dead seat relaunched" "$B/watch.sh once | grep -q 'w1 relaunched' && until_ \"[ \$(wc -l < $X/fake.log) -ge 2 ]\""
touch "$X/die"; $F say w1 die; for _ in 1 2 3; do sleep 0.4; $B/watch.sh once >/dev/null; done
ok "3 deaths in 60s = parked crash loop" "test -e $S/parked/w1 && grep -q 'w1 crash loop' $S/alerts.log"
rm -f "$X/die"
ok "digest prints changes, then nothing" "[ -n \"\$($B/watch.sh digest)\" ] && [ -z \"\$($B/watch.sh digest)\" ]"
ok "stop forgets the seat" "$F stop w1 && ! test -e $S/launch/w1 && ! $F peek w1"
ok "down kills the private server" "$F down && ! tmux -L fleet-kit-test has-session -t fleet"

echo "-- claim.sh"
C=$B/claim.sh
ok "w1 claims src/" "FLEET_NAME=w1 $C claim src/ | grep -qx src"
ok "w2 overlap (src/a.js) refused" "! FLEET_NAME=w2 $C claim src/a.js"
ok "w2 glob overlap (**/*.js hits src/a.js) refused" "! FLEET_NAME=w2 $C claim '**/*.js'"
ok "w2 disjoint docs/* ok" "FLEET_NAME=w2 $C claim 'docs/*'"
ok "bad paths refused (.. /abs .)" "! $C claim ../x && ! $C claim /etc && ! $C claim ."
echo b >> src/a.js; echo y >> docs/x.md
FLEET_NAME=w1 $C claim newarea/ >/dev/null   # claimed but empty: must not swallow the rest of the ship
ok "w1 ship commits only its claims (an empty claim does not block it)" "FLEET_NAME=w1 $C ship 'w1 work' && git show --stat HEAD | grep -q src/a.js && ! git show --stat HEAD | grep -q docs"
ok "release all frees src/ for w2" "FLEET_NAME=w1 $C release all && FLEET_NAME=w2 $C claim src/a.js"
ok "just fleet claim keeps the glob unexpanded" "FLEET_NAME=w3 just fleet claim 'kit/*' && grep -qxF 'w3 kit/*' $S/claims"

echo "-- gate.sh"
G=$B/gate.sh
ok "lint pass: gated one-liner" "$G lint 'test -f src/a.js && echo A-OK || { echo A-MISSING; exit 1; }'"
ok "lint fail: no hard gate" "! $G lint 'echo hi'"
ok "lint fail: \$VAR in single-quoted sed" "! $G lint \"sed -i 's/x/\\\$NAME/' f && echo A-OK || { echo A-MISSING; exit 1; }\""
ok "lint fail: two lines" "! $G lint \$'true\nfalse'"
id=$($G add 'test -f src/a.js && echo A-OK || { echo A-MISSING; exit 1; }' 'check a.js' | grep -oE 'g[0-9a-f]{6}' | head -1)
ok "add queues a row" "[ -n '$id' ] && $G list | grep -q '$id \\[pending\\]'"
ok "result pending = exit 2" "$G result $id; [ \$? -eq 2 ]"
ok "run go refused inside a seat" "! FLEET_ROLE=worker $G run go $id"
ok "human run go → ok, result 0" "$G run go $id > $X/go.out && grep -q A-OK $X/go.out && $G result $id"
bad=$($G add 'test -f nope && echo N-OK || { echo N-MISSING; exit 1; }' 'missing' | grep -oE 'g[0-9a-f]{6}' | head -1)
ok "failing row stops with rc 1" "! $G run go $bad; ! $G result $bad && grep -qx 1 $S/gate/$bad.rc"

echo "-- mine.sh"
H=$X/home; P="$H/.claude/projects/$(sed 's/[^A-Za-z0-9]/-/g' <<<"$(realpath "$R")")"; mkdir -p "$P"
for i in 1 2 3; do printf '%s\n' "{\"message\":{\"content\":[{\"type\":\"tool_use\",\"name\":\"Bash\",\"id\":\"a$i\",\"input\":{\"command\":\"npm test -- --watch=false\"}}]}}" \
  "{\"message\":{\"content\":[{\"type\":\"tool_result\",\"tool_use_id\":\"a$i\",\"content\":\"$(head -c 900 /dev/zero | tr '\0' x)\",\"is_error\":false}]}}" >> "$P/s.jsonl"; done
ok "mine ranks the repeated command" "HOME=$H just fleet mine 5 > $X/m.out && grep -q 'npm test -- --watch' $X/m.out && grep -q '^estimate: 3 repeated' $X/m.out"
ok "mine with no transcripts says so" "HOME=$X/nohome $B/mine.sh | grep -q 'no transcripts'"

echo "-- statusline.sh"
out=$(echo '{"session_name":"w5","context_window":{"total_input_tokens":42123},"rate_limits":{"five_hour":{"used_percentage":12.5},"seven_day":{"used_percentage":30}}}' | $B/statusline.sh)
ok "bar shows name, k tokens, 5h/7d" "[ '$out' = 'w5 · 42k · 5h 12% · 7d 30%' ]"
ok "json written (tok/q5h/q7d)" "jq -e '.tok == 42123 and .q5h == 12.5 and .q7d == 30' $S/w5.json"
echo '{"tok":9000,"q5h":90,"q7d":20}' > $S/w6.json
ok "just fleet usage: tokens, max quota, WARN ≥85%" "just fleet usage > $X/u.out && grep -q 'w5 *42k' $X/u.out && grep -q '5h 90%' $X/u.out && grep -q '^WARN' $X/u.out"
ok "settings.json valid, points at statusline" "jq -e '.statusLine.command | test(\"statusline.sh\")' .fleet/settings.json"

echo "== kit test: $pass ok, $fail fail"; (( fail == 0 ))
