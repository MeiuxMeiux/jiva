#!/usr/bin/env bash
# doctor-dash — dash.sh against a scratch TARGET in /tmp on a scratch port (never the live dash): seed two flags,
# a decision + a protected ask, a stale lease, comb lines + burn markers, a notify.log; curl /flags /asks /lease
# /comb /alerts and assert the JSON shape; static files still served, comb.log not; delete the lease → none; css never-grey
# scrollbars + no unsafe-inline CSP + fonts/ 200; scratch git repo → /commits shape/pagination/400, /commit/<sha> diffstat;
# snapshot.json allowlist/no-path/no-text + phone.{html,css,js} 200 + phone CSP; portraits 200 + party chips (dash + phone); trailer-less commit soul = desk;
# /history shape/pagination/kind+name filter/400s + /history/summary buckets ≤200 on a seeded history.jsonl;
# unpinned stop+start keeps the port, a taken port re-rolls. Stops the server. Prints ok/FAIL; exit 1 on any FAIL.
set -uo pipefail
H="$(cd "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")/.." && pwd)"
S="$(mktemp -d /tmp/jiva-doctor-XXXXXX)"; J="$S/.jiva"
dash() { JIVA_TARGET="$S" JIVA_DASH_PORT="$P" JIVA_LEASE_TTL=90 "$H/core/dash.sh" "$@"; }
trap 'dash stop >/dev/null 2>&1; rm -rf "$S"' EXIT
bad=0
ok() { printf 'ok    dash %s\n' "$1"; }
no() { printf 'FAIL  dash %s\n' "$1"; bad=1; }
t() { local l=$1; shift; if "$@"; then ok "$l"; else no "$l"; fi; }
get() { curl -sf --max-time 3 "${U}$1"; }
jt() { jq -e "$2" <<<"$(get "$1")" >/dev/null 2>&1; }   # endpoint jq-filter → true?

now=$(date +%s); mkdir -p "$J/flags" "$J/asks" "$J/lease"
printf 'first line\nlast line\n' > "$J/flags/storm"; echo stale > "$J/flags/lease-stale"
jq -nc --argjson ts $((now - 120)) '{id:"aa11", ts:$ts, from:"w1", class:"decision", q:"pick a port", opts:[], default:"1", deadline:0}' \
  > "$J/asks/open.jsonl"
jq -nc --argjson ts "$now" '{id:"bb22", ts:$ts, from:"w2", class:"deploy", q:"ship it?", opts:[], default:"no", deadline:0}' \
  >> "$J/asks/open.jsonl"
echo "$((now - 400)) sid-doc -" > "$J/lease/queen"
jq -nc --argjson ts "$now" '{ts:$ts, sessions:[{name:"w1", tok:50000}, {name:"w2", tok:20000}, {name:"/x/y", tok:1}]}' > "$J/state.json"
hm=$(date +%H:%M); mkdir -p "$J/nudged"; echo "2 5000" > "$J/nudged/w1.last"; echo "1 15000" > "$J/nudged/w2.last"
{ for i in $(seq 1 22); do echo "$hm w2     note step $i"; done; echo "$hm w1     done: shipped the thing"; } > "$J/comb.log"
{ for i in $(seq 1 23); do echo "$((now - 600 + i)) alert $i"; done; echo "junk line"; echo "$now newest: lease stale"; } > "$J/notify.log"

{ for i in $(seq 1 300); do echo "{\"ts\":$((now - 3000 + i * 10)),\"kind\":\"tok\",\"who\":\"watchdog\",\"tok\":$((i * 1000)),\"s\":{\"w1\":$i},\"q5h\":$((i / 4)),\"q7d\":null}"; done
  for i in 1 2 3 4 5; do echo "{\"ts\":$((now - 50 + i)),\"kind\":\"claim\",\"who\":\"w1\",\"n\":$i,\"secret\":\"x\"}"; done
  echo '{"ts":'$((now - 40))',"kind":"zzz","who":"w1"}'; echo 'not json'; echo '{"ts":'$((now - 30))',"kind":"ship","who":"w1","sha":"abc1234"}'
  echo '{"ts":'$((now - 20))',"kind":"life","who":"watchdog","name":"w2","why":"rotate","tok":9}'
  echo '{"ts":'$((now - 10))',"kind":"trip","who":"watchdog","name":"w2","trip":"burn"}'; echo '{"ts":'"$now"',"kind":"ask","who":"w1","id":"cc33","class":"spend"}'
} > "$J/history.jsonl"
g() { git -C "$S" -c user.name="Doc Tor" -c user.email=d@t "$@" >/dev/null; }
g init -q; for i in $(seq 1 7); do echo "$i" > "$S/f$i"; g add "f$i"; g commit -qm "c$i" -m "body $i"; done
g commit -q --allow-empty -m "c8 soul" -m "line one" -m "jiva: w4"   # newest; trailer soul
for _ in 1 2 3; do P=$(shuf -i 40000-60000 -n 1); U="$(dash start 2>/dev/null)" && break; done
t "starts on scratch port $P" test -n "${U:-}"
snap() { JIVA_TARGET="$S" JIVA_LEASE_TTL=90 "$H/core/snapshot.sh" >/dev/null; get snapshot.json; }
t "snapshot.json: allowlisted keys only" eval 'jq -e "(keys == [\"asks\",\"flags\",\"lease\",\"live\",\"quota\",\"sessions\",\"state_ts\",\"ts\"])
  and all(.sessions[]; keys == [\"color\",\"name\",\"slot\",\"status\",\"tok\",\"verb\"]) and all(.asks[]; keys == [\"age\",\"class\",\"id\"])
  and all(.flags[]; keys == [\"age\",\"name\"]) and (.asks | length) == 2 and (.sessions[0] | .slot == 1 and .verb == \"done\")" <<<"$(snap)" >/dev/null'
t "snapshot.json: no \"/\" path, no ask/comb text" eval 'sj="$(snap)"; [[ -n $sj && $sj != */* && $sj != *"pick a port"* && $sj != *shipped* ]]'
t "snapshot: soul binding wins (w1→slot 3), no .soul → wN→N" eval 'jq -c ".sessions[0].soul = {name: \"Ash\", slot: 3, color: null}" "$J/state.json" > "$J/st.tmp" &&
  mv "$J/st.tmp" "$J/state.json" && jq -e "(.sessions[0] | .name == \"w1\" and .slot == 3) and .sessions[1].slot == 2" <<<"$(snap)" >/dev/null'
t "phone.html + phone.css + phone.js served 200" eval 'get phone.html >/dev/null && get phone.css >/dev/null && get phone.js >/dev/null'
t "phone.html: CSP no unsafe-inline, no inline style/script" eval 'ph="$(get phone.html)"; grep -q "script-src '"'self'"'" <<<"$ph" &&
  ! grep -qiE "unsafe-inline|<style|style=|<script>" <<<"$ph"'
t "avatars/01.webp portrait served 200 (image/webp)" grep -qi '^content-type: image/webp' <(curl -sf -D - -o /dev/null --max-time 3 "${U}avatars/01.webp")
t "dash.js prefers pack portrait, svg fallback; party strip" eval 'dj="$(get dash.js)"; grep -q "p.portrait" <<<"$dj" && grep -q "sl.portrait, sl.avatar" <<<"$dj" &&
  get "" | grep -q "id=\"party\"" && get dash-panels.js | grep -q "function party"'
t "phone shows a party chip (portrait → svg → initial)" eval 'pj="$(get phone.js)"; get phone.html | grep -q "id=\"party\"" &&
  grep -q "p.portrait, p.avatar" <<<"$pj" && grep -q "ss.map(chip)" <<<"$pj" && get phone.css | grep -q "^\.chip "'
t "/flags: 2 named, age + first/last" jt flags 'length == 2 and (map(.name) | sort) == ["lease-stale","storm"] and
  (.[] | select(.name == "storm") | .first == "first line" and .last == "last line" and (.age | type) == "number")'
t "/asks: id/class/text/age/protected" jt asks 'length == 2 and .[0] == {id:"aa11", class:"decision", text:"pick a port",
  age:.[0].age, protected:false} and .[0].age >= 119 and .[1].class == "deploy" and .[1].protected == true'
t "/lease: stale + age (>3×TTL)" jt lease '.state == "stale" and .age >= 400'
echo "$now sid-doc -" > "$J/lease/queen"; t "/lease: fresh after refresh" jt lease '.state == "fresh" and .age < 60'
rm "$J/lease/queen"; t "/lease: none without a file" jt lease '. == {state:"none", age:null}'
t "/comb: last per session {name,ts,age,verb,text}" jt comb '(.last | length) == 2 and (.last[] | select(.name == "w1"))
  == {name:"w1", ts:"'"$hm"'", age:(.last[] | select(.name == "w1") | .age), verb:"done", text:"shipped the thing"}
  and (.last[] | select(.name == "w2") | .text == "step 22" and .verb == "note" and .age < 120)'
t "/comb: tail = last 20 overall" jt comb '(.tail | length) == 20 and .tail[-1].name == "w1" and .tail[0].text == "step 4"'
t "/comb: quiet = tok +45k past the burn marker" jt comb '.quiet == ["w1"]'
t "/alerts: last 20, newest first, {ts,age,text}" jt alerts 'length == 20 and .[0] == {ts:'"$now"', age:.[0].age,
  text:"newest: lease stale"} and .[0].age < 60 and .[1].text == "alert 23" and .[-1].text == "alert 5" and (map(.ts) | . == (sort | reverse))'
rm "$J/notify.log"; t "no notify.log → []" jt alerts '. == []'
rm "$J/comb.log"; t "no comb.log → empty /comb" jt comb '.last == [] and .tail == []'
rm -r "$J/flags" "$J/asks"; t "empty dirs → []" jt flags '. == []'; t "no open.jsonl → []" jt asks '. == []'
t "content-type json" grep -qi '^content-type: application/json' <(curl -s -D - -o /dev/null --max-time 3 "${U}lease")
t "index.html + dash.js + dash-panels.js + state.json served" eval 'get "" >/dev/null && get dash.js >/dev/null &&
  get dash-panels.js >/dev/null && get state.json >/dev/null'
t "page loads dash-panels.js before dash.js" eval 'get "" | grep -o "src=\"dash[-a-z]*\.js" | tr "\n" " " | grep -q "panels.js.*dash.js"'
t "comb.log file itself not reachable" eval '! get comb.log >/dev/null && ! get ../comb.log >/dev/null'
# shellcheck disable=SC2034  # sb/page/p2 are read inside t … eval strings
for c in dash.css dash-parts.css phone.css; do css="$(get "$c")"; sb="$(sed "s:/\*.*\*/::g" <<<"$css" | grep -i scrollbar)"   # comments stripped
  t "$c served, scrollbar-color uses palette hexes" eval 'grep -qiE "scrollbar-color: *#(ef4fbc|00ffd8|21ff00) +#060128" <<<"$sb"'
  t "$c: no grey in scrollbar rules" eval '! grep -qiE "#888|#999|#ccc|gr[ae]y|rgba?\( *([0-9]+) *, *\1 *, *\1 *[,)]" <<<"$sb"'
done
# shellcheck disable=SC2034
page="$(get "")"; t "CSP lacks 'unsafe-inline', no inline <style>/style=" eval '! grep -qiE "unsafe-inline|<style|style=" <<<"$page"'
t "CSP: style-src + font-src 'self'" eval 'grep -q "style-src '"'self'"'; font-src '"'self'"'" <<<"$page"'
t "fonts/ serves woff2 200, not the OFL txt" eval 'curl -sf -o /dev/null --max-time 3 "${U}fonts/bricolage-grotesque-latin-wght.woff2" &&
  curl -sf -o /dev/null --max-time 3 "${U}fonts/jetbrains-mono-latin-wght.woff2" && ! get fonts/OFL-JetBrainsMono.txt >/dev/null'
t "/commits: {sha,subject,soul,ts,files} newest first" jt commits 'length == 8 and .[0].subject == "c8 soul" and .[0].soul == "w4"
  and .[0].files == 0 and .[1] == {sha:.[1].sha, subject:"c7", soul:"desk", ts:.[1].ts, files:1} and (.[1].sha | test("^[0-9a-f]{40}$"))'
p1="$(get 'commits?n=3')"; b="$(jq -r '.[-1].sha' <<<"$p1")"
# shellcheck disable=SC2034
p2="$(get "commits?n=3&before=$b")"
t "/commits?n=3 + before= pages, no overlap" eval 'jq -e "length == 3" <<<"$p1" >/dev/null && jq -e "length == 3 and .[0].subject == \"c5\"" <<<"$p2" >/dev/null'
t "/commits before=root → []" jt "commits?before=$(git -C "$S" rev-list --max-parents=0 HEAD | cut -c1-12)" '. == []'
code() { curl -s -o /dev/null -w '%{http_code}' --max-time 3 "${U}$1"; }
t "400 on bad sha / n out of range, 404 unknown" eval '[[ $(code "commits?before=zzz1234") == 400 && $(code "commits?n=101") == 400 &&
  $(code "commits?n=x") == 400 && $(code "commit/HEAD") == 400 && $(code "commit/abc12;rm") == 400 && $(code commit/0000000) == 404 ]]'
t "/commit/<sha>: subject, body, diffstat only" jt "commit/$(jq -r '.[1].sha' <<<"$p1")" '.subject == "c7" and .body == "body 7"
  and .stat == [{file:"f7", add:1, del:0}] and (keys == ["body","sha","stat","subject"])'
t "/commit: trailer skipped in body" jt "commit/$(jq -r '.[0].sha' <<<"$p1")" '.body == "line one" and .stat == []'
t "/history: newest first, allowlisted fields, unknown kind/junk skipped" jt 'history?n=5' 'length == 5 and .[0] == {ts:'"$now"',
  kind:"ask", who:"w1", id:"cc33", class:"spend"} and (map(.kind) | index("zzz") == null) and .[4] == {ts:'$((now - 45))', kind:"claim", who:"w1", n:5}'
t "/history?before= pages by ts, no overlap" jt "history?n=2&before=$((now - 46))" 'map(.n) == [3,2]'
t "/history kind + name filters" eval 'jq -e "length == 2 and all(.[]; .name == \"w2\")" <<<"$(get "history?kind=life,trip&name=w2")" >/dev/null &&
  jq -e "length == 6 and all(.[]; .who == \"w1\")" <<<"$(get "history?kind=claim,ship&name=w1")" >/dev/null && jt "history?n=500" "length == 309"'
t "/history 400 on bad n/before/kind/name" eval '[[ $(code "history?n=0") == 400 && $(code "history?n=501") == 400 && $(code "history?n=x") == 400 &&
  $(code "history?before=abc") == 400 && $(code "history?kind=zzz") == 400 && $(code "history?name=a/b") == 400 ]]'
t "/history/summary: counts, sessions, ≤200 buckets + tok points" jt history/summary '.counts == {tok:300, claim:5, ship:1, life:1, trip:1, ask:1}
  and .sessions.w2 == {lives:1, ships:0, trips:1, asks:0, lane:.sessions.w2.lane} and .sessions.w1.ships == 1 and .sessions.w1.asks == 1
  and .buckets <= 200 and (.tok | length) <= 200 and (.tok | length) > 100 and .tok[-1][1] == 300000 and all(.sessions[].lane | keys[]; tonumber < 200)'
t "dash-history.js served + loaded last" eval 'get dash-history.js >/dev/null && get "" | grep -o "src=\"dash[-a-z]*\.js" | tail -1 | grep -q history'
t "bound to 127.0.0.1 only" test "${U%%:[0-9]*}" = "http://127.0.0.1"
dash stop >/dev/null; t "stop kills it" eval '! get lease >/dev/null'
ud() { JIVA_TARGET="$S" JIVA_LEASE_TTL=90 env -u JIVA_DASH_PORT "$H/core/dash.sh" "$@"; }   # unpinned
t "unpinned stop+start keeps the port" eval '[[ $(ud start 2>/dev/null) == "http://127.0.0.1:$P/" ]]'
ud stop >/dev/null; python3 -c "import socket,time;s=socket.socket();s.setsockopt(socket.SOL_SOCKET,socket.SO_REUSEADDR,1)
for _ in range(20):
  try: s.bind((\"127.0.0.1\",$P)); break
  except OSError: time.sleep(0.1)
s.listen();time.sleep(8)" & hog=$!; sleep 0.5
t "taken port re-rolls" eval 'U2="$(ud start 2>/dev/null)"; [[ -n $U2 && $U2 != *":$P/" ]]'
ud stop >/dev/null; kill "$hog" 2>/dev/null
exit $bad
