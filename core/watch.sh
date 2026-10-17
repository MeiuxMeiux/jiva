#!/usr/bin/env bash
# watch — one live terminal view for the human, redrawn every ${JIVA_WATCH_EVERY:-2}s:
#   status line (core/status.sh line 1 + quota) · session rows · FLAGS · OPEN ASKS · ALERTS · last board lines.
# Keys: q quit · a answer (`<id> [text]` → jiva answer) · any other key redraws. Piped (non-tty): one frame, exit 0.
# The first line goes red when it says lease stale / runtime down / protected ask / quota ≥85% (plain if NO_COLOR).
set -uo pipefail
# shellcheck source=core/lib.sh
source "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")/lib.sh"
QUIET="${JIVA_QUIET:-40000}"   # tok since the last board line before a row reads "quiet"
PROTECTED="permission deploy spend destructive sudo remote license"   # mirrors ASK_PROTECTED in core/asks.sh
TTY=0; [[ -t 1 ]] && TTY=1
RED="" OFF=""
if (( TTY )) && [[ -z ${NO_COLOR:-} ]] && command -v tput >/dev/null 2>&1; then
  RED="$(tput setaf 1 2>/dev/null)$(tput bold 2>/dev/null)"; OFF="$(tput sgr0 2>/dev/null)"
fi

head_line() { # status.sh line 1 (ends with the dash URL) + quota; "runtime down" when status has no state
  local s q
  s="$("$JIVA_HOME/core/status.sh" 2>/dev/null)"; local rc=$?; s="${s%%$'\n'*}"
  if (( rc == 0 )) && [[ -n $s ]]; then
    q="$(jq -r '[if .q5h then "q5h \(.q5h)%" else empty end, if .q7d then "q7d \(.q7d)%" else empty end]
      | join(" · ")' "$J/state.json" 2>/dev/null)"
    printf '%s%s' "$s" "${q:+ · $q}"
  elif [[ $s == *"runtime down"* ]]; then printf '%s' "$s"   # status.sh's own reason (tmux down; carries dash)
  else
    printf 'runtime down — no state.json in %s (`jiva up`) · %s' "$J" "$("$JIVA_HOME/core/status.sh" dash)"
  fi
}

alarm() { # line extra-words → alarm words to append (empty = calm)
  local w=""
  [[ $1 == *"lease stale"* ]] && w+=" LEASE-STALE"
  [[ $1 == *"runtime down"* ]] && w+=" RUNTIME-DOWN"
  [[ -n $2 ]] && w+=" PROTECTED-ASK"
  jq -e '(.q5h // 0) >= 85 or (.q7d // 0) >= 85' "$J/state.json" >/dev/null 2>&1 && w+=" QUOTA≥85%"
  fresh_alert && w+=" ALERT"
  printf '%s' "$w"
}

sessions() { # rows + "· Nm ago verb text" from the session's last board line; "quiet" = tok +>QUIET since it
  [[ -s $J/state.json ]] || return 0
  local nm r name x y lt last cols tok; nm=$(( 10#$(date +%H) * 60 + 10#$(date +%M) )); cols=$(tput cols 2>/dev/null || echo 120)
  (( TTY )) || cols=${COLUMNS:-120}
  while IFS= read -r r; do
    read -r name x y _ <<<"$r"; [[ $x == "·" ]] && name=$y   # "Ash · w1 …" (soul label) or "w1 …"
    last="$(awk -v n="$name" -v nm="$nm" '$2 == n { split($1, t, ":"); a = (nm - t[1] * 60 - t[2] + 1440) % 1440
      v = $3; sub(/:$/, "", v); $1 = $2 = $3 = ""; sub(/^ +/, ""); l = a "m ago " v " " $0 } END { print l }' \
      < <(board_tail 2000))"   # lines past JIVA_MSG_TTL are hidden (lib.sh board_tail)
    lt=""; [[ -r $J/nudged/$name.last ]] && read -r _ lt < "$J/nudged/$name.last"
    tok="$(jq -r --arg n "$name" '.sessions[] | select(.name == $n) | .tok // 0' "$J/state.json" 2>/dev/null | head -1)"
    [[ $lt =~ ^-?[0-9]+$ && ${tok:-0} =~ ^[0-9]+$ ]] && (( tok - lt > QUIET )) && r+="  quiet"
    r+="  · ${last:-(no report yet)}"; printf '%s\n' "${r:0:cols}"
  done < <(jq -r '.sessions[]? | "  \(if .soul.slot != null then "\(.soul.name) · \(.name)" else .name end)\t\(.status)\t\((.tok // 0) / 1000 | floor)k\t\(.pct // 0)%\t\(.waiting // "-")"' \
    "$J/state.json" | column -t -s $'\t')
}

flags() {
  local f out=""
  for f in "$J"/flags/*; do [[ -e $f ]] && out+=" ${f##*/}"; done
  [[ -n $out ]] && printf 'FLAGS:%s   (clear: rm .jiva/flags/<name>)\n' "$out"
}

asks() { # block of open asks; protected classes marked [!]
  [[ -s $J/asks/open.jsonl ]] || return 0
  echo "OPEN ASKS ($(wc -l < "$J/asks/open.jsonl")) — jiva answer <id> [text]  (a = answer here)"
  jq -r --argjson now "$(date +%s)" --arg p " $PROTECTED " \
    '(.class // "decision") as $c | "  \(if ($p | contains(" " + $c + " ")) then "[!]" else "   " end) \(.id)  \($c)  " +
    "\(($now - .ts) / 60 | floor)m  \(.from): \(.q)"' "$J/asks/open.jsonl"
}

alerts() { # last 3 notify.log lines (core/notify.sh toast) as "ALERTS: Nm ago text · …"; hidden when none
  [[ -s $J/notify.log ]] || return 0
  tail -n 3 "$J/notify.log" | awk -v now="$(date +%s)" '{ a = int((now - $1) / 60); $1 = ""; sub(/^ /, "")
    o = a "m ago " $0 (NR > 1 ? " · " o : "") } END { if (o != "") print "ALERTS: " o }'
}

fresh_alert() { # 0 when the newest alert is < 5 min old
  local ts; ts="$(tail -n 1 "$J/notify.log" 2>/dev/null)"; ts="${ts%% *}"
  [[ $ts =~ ^[0-9]+$ ]] && (( $(date +%s) - ts < 300 ))
}

protected_open() {
  [[ -s $J/asks/open.jsonl ]] || return 0
  jq -r --arg p " $PROTECTED " '(.class // "decision") as $c | select($p | contains(" " + $c + " ")) | .id' \
    "$J/asks/open.jsonl" 2>/dev/null | head -1
}

frame() { # build the whole frame in one variable
  local h a top body rows used n
  h="$(head_line)"; a="$(alarm "$h" "$(protected_open)")"
  if [[ -n $a ]]; then top="${RED}${h} !!${a}${OFF}"; else top="$h"; fi
  body="$(sessions)"$'\n'"$(flags)"$'\n'"$(asks)"$'\n'"$(alerts)"
  body="$(sed '/^$/d' <<<"$body")"
  rows=$(tput lines 2>/dev/null || echo 40); (( TTY )) || rows=${LINES:-40}
  used=$(( 3 + $(grep -c '' <<<"$body") ))
  n=$(( rows - used - 1 )); (( n < 5 )) && n=5
  F="$top"$'\n'"$body"$'\n'"-- board (last $n)"$'\n'"$(board_tail "$n")"
  (( TTY )) || return 0
  F+=$'\n'"[q] quit  [a] answer  [any] redraw   $(date +%H:%M:%S)"
  local l cols out=""; cols=$(tput cols 2>/dev/null || echo 120)   # clip, so long lines never wrap the header away
  while IFS= read -r l; do out+="${l:0:cols}"$'\n'; done <<<"$F"
  F="${out%$'\n'}"
}

if (( ! TTY )); then frame; printf '%s\n' "$F"; exit 0; fi

answer_prompt() {
  local line id text
  tput cnorm 2>/dev/null; stty echo 2>/dev/null
  printf '\nanswer <id> [text] (empty = cancel): '; IFS= read -r line </dev/tty || line=""
  stty -echo 2>/dev/null; tput civis 2>/dev/null
  [[ -n $line ]] || return 0
  id="${line%% *}"; text=""; [[ $line == *" "* ]] && text="${line#* }"
  "$JIVA_HOME/core/jiva.sh" answer "$id" "$text" 2>&1 | tail -1; sleep 1
}

trap 'stty echo 2>/dev/null; tput cnorm 2>/dev/null; tput rmcup 2>/dev/null; exit 0' EXIT INT TERM
tput smcup 2>/dev/null; tput civis 2>/dev/null; stty -echo 2>/dev/null
while :; do
  frame
  printf '%s%s' "$(tput home 2>/dev/null)$(tput ed 2>/dev/null)" "$F"
  key=""; IFS= read -rsn1 -t "${JIVA_WATCH_EVERY:-2}" key </dev/tty || true
  case $key in
    q|Q) exit 0 ;;
    a|A) answer_prompt ;;
  esac
done
