#!/usr/bin/env bash
# check — budgets as tests, run in the current dir: files ≤150 lines, notes ≤30, scripts parse,
# json valid, shellcheck clean. `just check` calls this; `jiva report done` runs it on targets without one.
# JIVA_BUDGETS=0 drops the two line budgets (parse/json/shellcheck still run).
set -uo pipefail; bad=0
skills() {   # every plugin skill stays a symlink (worktree + index mode 120000) to a real file under core/roles/
  local f r m
  for f in plugin/skills/*/SKILL.md; do
    [[ -e $f || -L $f ]] || continue
    r="$(readlink -f "$f")"; m="$(git ls-files -s -- "$f" | cut -c1-6)"
    if [[ ! -L $f || ! -f $r || $r != "$(pwd -P)"/core/roles/* || ${m:-120000} != 120000 ]]; then
      echo "FAIL plugin skill $(basename "$(dirname "$f")") is not a symlink into core/roles (edit the role via the keeper)"; bad=1
    fi
  done
}
skills; [[ ${1:-} == skills ]] && exit $bad   # `check.sh skills`: only this assert (doctor runs it in scratch)
for f in $(git ls-files core scripts plugin justfile); do
  [[ -f $f ]] || continue   # listed but deleted in the working tree (a worker mid-change)
  (( ${JIVA_BUDGETS:-1} == 0 || $(wc -l < "$f") <= 150 )) || { echo "over 150 lines: $f"; bad=1; }
  [[ $f == *.sh ]] && { bash -n "$f" || bad=1; }
  [[ $f == *.json ]] && { jq empty "$f" || bad=1; }
done
for f in notes/*.md; do [[ -e $f && ${JIVA_BUDGETS:-1} != 0 ]] && { (( $(wc -l < "$f") <= 30 )) || { echo "over 30 lines: $f"; bad=1; }; }; done
[[ -x plugin/check.sh ]] && { plugin/check.sh || bad=1; }   # plugin skills name only real verbs/recipes
[[ -f scripts/readme-drift.py ]] && { python3 -I scripts/readme-drift.py || bad=1; }   # README/QUICKSTART vs CLI + site
if command -v shellcheck >/dev/null && [[ -n $(git ls-files '*.sh') ]]; then
  # shellcheck disable=SC2046
  shellcheck -S warning $(git ls-files '*.sh' | while read -r f; do [[ -f $f ]] && echo "$f"; done) || bad=1
elif [[ -n $(git ls-files '*.sh') ]]; then echo "WARN check: shellcheck not on PATH — lint skipped"; fi
if command -v claude >/dev/null && [[ -f plugin/.claude-plugin/plugin.json ]]; then   # warnings ok, errors fail
  out="$(claude plugin validate plugin/ 2>&1)" || { echo "$out"; bad=1; }
fi
exit $bad
