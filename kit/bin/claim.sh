#!/usr/bin/env bash
# claim — cells own PATHS, not topics. .hive/state/claims holds "<cell> <glob>" lines; globs never overlap.
#   claim.sh claim <glob…>     add claims for $FLEET_NAME (default: desk); refused if any overlaps another cell's
#   claim.sh release <glob…|all>  drop your own claims
#   claim.sh list [cell]       every claim (or one cell's globs)
#   claim.sh ship "<msg>"      stage + commit ONLY your claimed paths (pathspec), never `add -A`
# A dir claim (src or src/) covers everything under it. Overlap = one glob matches the other, or a file in
# the repo matches both. All writes hold an flock on .hive/state/claims.lock.
set -euo pipefail
ROOT="${FLEET_ROOT:-$(git rev-parse --show-toplevel)}"; S="$ROOT/.hive/state"; C="$S/claims"
ME="${FLEET_NAME:-desk}"; mkdir -p "$S"; touch "$C"
die() { echo "claim: $*" >&2; exit 1; }
norm() { # glob → repo-relative, no trailing slash; refuses /abs, .. and the bare root
  local g=${1%/}; g=${g#./}
  [[ -n $g && $g != /* && $g != . && ! $g =~ (^|/)\.\.(/|$) && $g != '*' && $g != '**' ]] || die "'$1' must be a repo-relative subpath"
  printf '%s\n' "$g"
}
hit() { # pattern path → the path is the pattern, under it, or matches it (* spans /)
  # shellcheck disable=SC2053
  [[ $2 == $1 || $2 == $1/* ]]
}
files() { git -C "$ROOT" ls-files -co --exclude-standard 2>/dev/null; }
overlap() { # a b → 0 if the two globs can claim the same path
  hit "$1" "$2" || hit "$2" "$1" && return 0
  local f; while IFS= read -r f; do hit "$1" "$f" && hit "$2" "$f" && return 0; done < <(files)
  return 1
}

claim() {
  (($#)) || die "claim <glob…>"
  local g s q gs=(); for g; do gs+=("$(norm "$g")"); done
  exec 9> "$S/claims.lock"; flock 9
  for g in "${gs[@]}"; do
    while read -r s q; do
      [[ -n ${s:-} && $s != "$ME" ]] || continue
      overlap "$g" "$q" && die "$g overlaps $s's $q — refused (nothing claimed)"
    done < "$C"
  done
  for g in "${gs[@]}"; do grep -qxF -- "$ME $g" "$C" || echo "$ME $g" >> "$C"; done
  list "$ME"
}

release() {
  (($#)) || die "release <glob…|all>"
  exec 9> "$S/claims.lock"; flock 9
  local g keep; keep="$(cat "$C")"
  if [[ $1 == all ]]; then keep="$(awk -v m="$ME" '$1 != m' <<<"$keep")"
  else for g; do g="$(norm "$g")"; keep="$(grep -vxF -- "$ME $g" <<<"$keep" || true)"; done; fi
  printf '%s\n' "$keep" | sed '/^$/d' > "$C.tmp"; mv "$C.tmp" "$C"
  echo "claim: released for $ME: $*"
}

list() { if [[ -n ${1:-} ]]; then awk -v m="$1" '$1 == m { print $2 }' "$C"; else cat "$C"; fi; }

ship() {
  [[ -n ${1:-} ]] || die "ship \"<msg>\""
  local g p f gs=() fs=(); mapfile -t gs < <(list "$ME")
  ((${#gs[@]})) || die "$ME has no claims — nothing to ship"
  for g in "${gs[@]}"; do for p in ":(glob)$g" ":(glob)$g/**"; do   # one pathspec per add: a claim with no files yet
    git -C "$ROOT" add -A -- "$p" 2>/dev/null || true                 # must not abort the others (-A = deletions too)
  done; done
  while IFS= read -r -d '' f; do for g in "${gs[@]}"; do hit "$g" "$f" && { fs+=("$f"); break; }; done; done \
    < <(git -C "$ROOT" diff --cached --name-only -z)
  ((${#fs[@]})) || die "nothing changed under $ME's claims"
  git -C "$ROOT" commit -q -m "$1" -- "${fs[@]}"
  git -C "$ROOT" log -1 --format='claim: shipped %h %s'
}

[[ ${BASH_SOURCE[0]} == "$0" ]] || return 0
cmd=${1:-list}; shift || true
case $cmd in
  claim|release|list|ship) "$cmd" "$@" ;;
  *) echo "usage: claim.sh claim|release|list|ship …" >&2; exit 2 ;;
esac
