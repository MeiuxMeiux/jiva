#!/usr/bin/env bash
# mine — non-LLM justfile miner. Reads ~/.claude/projects/<slug>/*.jsonl (slug = TARGET, non-alnum → -),
# pairs every Bash tool_use with its tool_result, normalizes each command to a key (first token +
# subcommand + flags, args collapsed; ≤3 distinct statements per call joined " + ", echo/cd/printf dropped,
# heredoc writes → cat>file) plus bigrams of consecutive calls, and ranks them:
#   score = freq × median output bytes × (1 + retries)   retry = same key re-run ≤3 calls after an error
# Usage: mine.sh [n=10] [all]. Trivial keys (only cat/ls/sed/python3 -/…) are hidden unless `all`; a bigram
# needs both halves non-trivial. Calls made only of just/jiva are skipped; token-like strings redacted.
set -euo pipefail
# shellcheck source=core/lib.sh
source "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")/lib.sh"
n="${1:-10}"; all=false; [[ ${2:-} == all ]] && all=true
dir="$HOME/.claude/projects/$(sed 's/[^A-Za-z0-9]/-/g' <<<"$TARGET")"
shopt -s nullglob; files=("$dir"/*.jsonl)
(( ${#files[@]} )) || { echo "(no transcripts)"; exit 0; }

rows="$(jq -nr --argjson n "$n" --argjson all "$all" '
def plain: ["cat","ls","head","tail","grep","rg","sed","awk","wc","find","rm","mkdir","cp","mv","chmod",
  "touch","jq","sleep","bash","sh","diff","sort","uniq","test","stat","du","df","readlink","realpath",
  "dirname","basename","xargs","tr","cut","date","sha1sum","file","which","command","cat>file","python3"];
def sep: ["echo","printf","cd","source",".","true",":","for","done","fi","esac","[[","[","exit","set","shopt","sleep","command"];
# one statement (text before its first |) → "cmd [sub] -flags"; separators → ""; heredoc writes → cat>file
def segk: [splits("\\s+") | select(length > 0) | select(test("^[A-Za-z_][A-Za-z0-9_]*=") | not)]
  | until(length == 0 or (.[0] | IN("do","then","else","if","while","until","!","time") | not); .[1:])
  | if length == 0 then "" else .[0] as $c | ($c | sub(".*/"; "")) as $b
    | (if $b == "tmux" and .[1]? == "-L" then del(.[1, 2]) else . end)
    | if any(sep[]; . == $b) then ""
      elif $b == "cat" and any(.[]; startswith(">")) then "cat>file"
      else [$c]
        + (if length > 1 and (.[1] | test("^[a-z][a-z0-9-]*$")) and (any(plain[]; . == $b) | not)
           then [.[1]] else [] end)
        + [.[1:][] | select(startswith("-")) | select(test("^-[0-9]+$") | not) | sub("=.*"; "")]
        | join(" ") end end;
# whole command → up to 3 distinct statement keys joined " + " (heredoc bodies dropped, pipe tails ignored)
def key: gsub("<<-?\\s*[\"\\x27]?(?<t>[A-Za-z_]+)[\"\\x27]?(?<r>[^\\n]*)\\n[\\s\\S]*?\\n\\s*\\k<t>(?=\\n|$)"; "<<H\(.r)")
  | gsub("\\$\\([^()]*\\)|\"[^\"]*\"|\\x27[^\\x27]*\\x27"; "Q")
  | gsub("\\|\\||&&|;"; "\n") | [split("\n")[] | (split("|")[0] // "") | segk | select(. != "")]
  | reduce .[] as $k ([]; if index([$k]) then . else . + [$k] end) | .[:3] | join(" + ");
def trivial: split(" + ") | all(.[]; split(" ")[0] | sub(".*/"; "") as $b | any(plain[]; . == $b));
def skip: split(" + ") | all(.[]; test("^(\\S*/)?(just|jiva|jiva\\.sh)( |$)"));
def red: gsub("[A-Za-z0-9_-]{32,}"; "‹redacted›");
def bytes: if type == "string" then utf8bytelength
  elif type == "array" then map(.text? // "" | utf8bytelength) | add // 0 else 0 end;
def median: sort | .[length / 2 | floor];

# per session: ordered Bash uses + results by id
(reduce inputs as $l ({};
  input_filename as $f
  | reduce ($l.message.content? | arrays | .[]) as $c (.;
      if $c.type == "tool_use" and $c.name == "Bash" then
        .[$f].u += [{id: $c.id, cmd: ($c.input.command // "")}]
      elif $c.type == "tool_result" then
        .[$f].r[$c.tool_use_id] = {b: ($c.content | bytes), e: ($c.is_error // false)}
      else . end)))
| [.[] | (.r // {}) as $r
   | [(.u // [])[] | select($r[.id]?) | {k: (.cmd | key), ex: .cmd, b: $r[.id].b, e: $r[.id].e}]
   | select(length > 0)
   | . as $s
   | [range(length) as $i | $s[$i] + {t: (if $s[$i].e then
        any($s[$i + 1:$i + 4][]; .k == $s[$i].k) else false end)}]] as $sess
| ([$sess[][] | select(.k != "") | select($all or (.k | trivial | not))]
   + [$sess[] | . as $s | range(length - 1) as $i
      | select([$s[$i].k, $s[$i + 1].k] | all(.[]; . != "" and (trivial | not)))
      | {k: "\($s[$i].k) → \($s[$i + 1].k)", ex: "\($s[$i].ex) ⏎ \($s[$i + 1].ex)",
         b: ($s[$i].b + $s[$i + 1].b), t: ($s[$i].t or $s[$i + 1].t), skipk: [$s[$i].k, $s[$i + 1].k]}])
| map(select((.skipk // [.k]) | any(.[]; skip) | not))
| group_by(.k)
| map({k: .[0].k, ex: .[0].ex, f: length, rt: map(select(.t)) | length, m: (map(.b) | median)}
      | .s = .f * .m * (1 + .rt))
| map(select(.f > 1)) | sort_by(-.s) | .[:$n][]
| [.s, .f, "\(.rt * 100 / .f | floor)%", .m, (.k | red),
   (.ex | gsub("\\s+"; " ") | red | if length > 70 then .[:69] + "…" else . end)] | @tsv
' "${files[@]}")"

[[ -n $rows ]] || { echo "(no Bash calls)"; exit 0; }
{ printf 'score\tfreq\tretry\tmed_bytes\tkey\texample\n'; printf '%s\n' "$rows"; } | column -t -s $'\t'
